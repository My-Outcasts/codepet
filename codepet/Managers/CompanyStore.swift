// codepet/Managers/CompanyStore.swift
import Foundation
import Combine

/// The app's primary store — the single company (companies/{uid}) + the active
/// view. Native port of the web `useApp`/`lib/store`. Replaces ProjectStore's
/// role as the top-level store (ProjectStore/reflection are being retired).
@MainActor
final class CompanyStore: ObservableObject {
    @Published var view: AppView = .roadmap
    /// User's manual collapse of the docked copilot (session-only). The shell also
    /// auto-collapses on a narrow window via ShellLayout; this is the manual override.
    @Published var dockCollapsed: Bool = false
    /// Which settings section is open, or `nil` when settings is closed. Settings is an
    /// overlay rather than an `AppView`, so opening it never changes `view` and closing
    /// it needs no route to restore.
    @Published var settingsSection: SettingsSection?
    @Published private(set) var company: CompanyState = .empty
    @Published private(set) var isHydrating: Bool = false
    @Published private(set) var isOnboarding: Bool = false
    /// `chatMessages` is the ACTIVE thread's live working buffer — the view keeps
    /// rendering it exactly as before. `newChat`/`switchThread`/`deleteThread` flush
    /// the buffer into its outgoing `ChatThread` entry (in `threads`) and load the
    /// incoming one; a send just appends into this buffer and, at the end of the
    /// turn, flushes so the thread list's title/`updatedAt` stay current. Session-only
    /// (mirrors `chatMessages`'s own non-Codable, in-memory contract) — see `ChatThreads.swift`.
    @Published private(set) var chatMessages: [CopilotMessage] = []

    // MARK: - Coding agent (local edit_code)

    /// The project folder linked for the coding agent. Client-only; reset on account switch.
    @Published private(set) var activeProjectLink: ProjectLink?
    private static let activeProjectBookmarkKey = "cp_active_project_bookmark"

    /// The chat message a chat-triggered coding run anchors to, so its card renders
    /// inline right after that ask. `nil` for runs triggered outside chat (tasks/roadmap):
    /// those fall back to the transcript bottom.
    @Published var codingRunAnchorId: String?

    /// Drives local coding-agent runs. Lazy so the runner is built only on first use.
    /// The `-CODEPET_MOCK_CHAT` launch arg (via `MockChat.enabled`, same flag chat/task
    /// runs key off) swaps in `MockCodeRunner` (no `claude`, no cost) while keeping the
    /// real diff-review + git-commit engine, so the flow is free to test. `MockChat` is
    /// `#if DEBUG`-only, so the flag read is guarded and always `false` in Release.
    private var codingRunBag: AnyCancellable?
    lazy var codingRun: CodingRunCoordinator = {
        #if DEBUG
        let mock = MockChat.enabled
        #else
        let mock = false
        #endif
        let runner: CodeRunning = mock ? MockCodeRunner() : ClaudeCodeRunAdapter()
        let c = CodingRunCoordinator(runner: runner)
        // Re-publish the nested coordinator's changes so views observing only
        // CompanyStore re-render as the run progresses (otherwise the card "sticks").
        self.codingRunBag = c.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        return c
    }()

    /// The composer's in-progress text. Lives on the store, not the view, because the
    /// shell tears `CopilotChatView` down on every navigation and a roadmap dispatch
    /// now navigates to chat programmatically.
    @Published var chatDraft: String = ""
    /// Every thread that has EVER held a message this session, active or not.
    /// An in-progress "new chat" with nothing sent yet has no entry here (lazily
    /// created by `flushActiveThread` on its first non-empty flush).
    @Published private(set) var threads: [ChatThread] = []
    /// The thread `chatMessages` currently belongs to. Nil only before the very
    /// first message of the session is sent (no thread exists yet to point at).
    @Published private(set) var activeThreadId: String?
    @Published private(set) var isCompanionTyping = false
    /// True for the WHOLE duration of a chat send — from the placeholder's append
    /// until the stream (or its fallback) fully completes. Unlike `isCompanionTyping`
    /// (which flips off on the first delta, typing→streaming), this stays up while
    /// tokens are still arriving, so the UI can keep Send disabled for the entire
    /// stream instead of re-enabling mid-response. Reset alongside `isCompanionTyping`
    /// everywhere that already clears it (hydrate's account-switch branch, `reset()`,
    /// and `sendChat`'s unconditional tail) — never stuck true.
    @Published private(set) var isStreaming = false
    @Published private(set) var runningTaskIds: Set<String> = []
    /// Live parallel department-agent runs (the chat fan-out). Rendered as one
    /// AgentsWorkingRow; empty ⇒ no row. Seeded by `fanOutNextMoves`, cleared when
    /// the whole fan-out completes; each agent's draft lands in `chatMessages`.
    @Published var activeAgentRuns: [AgentRun] = []
    /// True while a fan-out is in flight — serializes it against a normal chat turn
    /// and disables the composer (same busy model as a single run).
    @Published private(set) var isFanningOut: Bool = false
    /// Max concurrent department agents per fan-out (bounds credit spend + latency).
    static let maxFanOut = 3
    @Published private(set) var runError: String?
    @Published private(set) var isGeneratingRoadmap = false
    /// The Company view's open department, if any — PROMOTED from AppShellView's
    /// former `@State private var selectedDept` so a chat `navigate(department)`
    /// action (via `activateNav`) can open it too, not just a tap in CompanyView.
    /// `AppShellView` reads/writes this directly; nil shows the department roster.
    @Published var selectedDeptKey: String?

    /// The hydrated company's id, needed for writes. Set by `hydrate`, cleared by `reset`.
    private(set) var companyId: String?

    /// Injectable so tests can supply a stub without Firestore.
    private let loader: (String) async -> CompanyState
    private let saver: (String, CompanyBrief) async -> Bool
    private let roadmapFetcher: (CompanyBrief, AppLanguage) async -> [RoadmapTask]
    private let tasksSaver: (String, [RoadmapTask]) async -> Bool
    private let chatSender: (CompanyChatRequest) async -> CompanyChatReply?
    /// Streaming counterpart of `chatSender`, injectable the same way (tests
    /// supply a synthetic `AsyncThrowingStream`). `chatSender` stays wired in
    /// as `sendChat`'s fallback — see its doc comment.
    private let chatStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error>
    /// The Virtual Company fan-out, injected exactly like `chatStreamer` so the
    /// handoff/escape-hatch/failure orderings can be driven from a synthetic stream
    /// with no network. Defaulted in the init BODY (not as a default argument) so the
    /// closure is formed inside this `@MainActor` type instead of in the nonisolated
    /// default-argument context, which is what makes `chatStreamer`'s default warn.
    private let vcRunner: (VirtualCompanyRequest) -> AsyncThrowingStream<VirtualCompanyEvent, Error>
    private let taskRunner: (RunTaskRequest) async -> RunTaskResponse?
    private let librarySaver: (String, [Deliverable]) async -> Bool
    private let toolsSaver: (String, [String]) async -> Bool
    private let companionSaver: (String, String) async -> Bool
    private let founderPrefsSaver: (String, FounderPrefs) async -> Bool
    private let introSeenSaver: (String, Date) async -> Bool
    private let enricher: (CompanyBrief) async throws -> CompanyBrief
    private let decisionsSaver: (String, [DecisionEntry]) async -> Bool
    private let decisionExtractor: (ApprovedDeliverableDTO, [DecisionEntry]) async -> [ExtractedDecision]
    /// Where "already asked this founder for runway + constraints" lives. Per company
    /// id, so it neither nags across launches nor leaks across accounts — see
    /// `VirtualCompanyInterviewFlag`.
    private let vcInterviewFlag: VirtualCompanyInterviewFlag

    /// Pushes `FounderPrefs.memoryEnabled` into `PetMemoryStore`, the DERIVED half of memory.
    /// A push (rather than a read) because the summarize enrichers reach that store
    /// statically through `.shared` and never see a company — and injectable because a test
    /// must be able to prove the switch travels without mutating a process-wide singleton.
    private let codingMemoryGate: (Bool) -> Void

    /// Bumped on every hydrate/reset; lets a suspended hydrate detect it has
    /// been superseded (account switch mid-flight) and discard its result
    /// instead of clobbering newer state.
    private var hydrationToken = 0

    /// The `hydrationToken` in effect when the current onboarding started. The
    /// model captures this BEFORE the enrich await and passes it to
    /// `finishOnboarding`; a finish only applies if it still matches — so an
    /// account switch during the enrich/save await can't write one account's
    /// brief into another's doc or clobber the newly-hydrated account.
    private(set) var onboardingToken = 0

    /// Bumped on every `updateFounderPrefs` that gets past its hydration guard; lets a
    /// suspended prefs write detect that a NEWER write on the same account started while
    /// it was awaiting Firestore, and discard its in-memory commit instead of clobbering
    /// the newer choice. Separate from `hydrationToken`, which only moves on an account
    /// switch and so cannot see two writes on one account.
    private var founderPrefsWriteToken = 0

    /// The founder's LATEST INTENDED preferences: `company.founderPrefs` plus every change
    /// committed since, including ones whose Firestore write has not returned yet. Nil when
    /// nothing is in flight.
    ///
    /// `company.founderPrefs` only catches up when a write completes, so a second panel
    /// committing inside that window and reading the visible value would carry the in-flight
    /// field's OLD value along with its own change — turn memory off, change a notification
    /// before the first write lands, and `memoryEnabled` comes back as `true`. Every change is
    /// therefore composed onto THIS value, so each commit contributes only its own field and
    /// the two changes accumulate instead of racing. Cleared by `hydrate`/`reset` so one
    /// account's in-flight intent can never be composed onto another's preferences.
    private var pendingFounderPrefs: FounderPrefs?

    /// First-run enrichment interview progress: the empty gaps to ask + the index
    /// we're on. Session-only, never persisted (mirrors the web useRef). Nil when
    /// no interview is active.
    /// `seedGreetingWhenDone` distinguishes the two interviews that share this queue.
    /// The first-run one hands off to byte's greeting when it empties; the Virtual
    /// Company one happens mid-session, where that greeting would read as amnesia.
    private var interviewState: (gaps: [InterviewGap], idx: Int, seedGreetingWhenDone: Bool)?

    /// In-flight Virtual Company runs, keyed by the message the room will occupy.
    /// Nobody awaits them — the room owns its own appended message, so it outlives
    /// byte's turn instead of holding `isStreaming` (and with it Send, New chat and
    /// the thread switcher) for the length of a run. Kept only so `reset()` can stop
    /// the outgoing account's runs, and so the deadline watchdog has something to
    /// cancel. Each run removes its own entry when it ends.
    private var vcTasks: [String: Task<Void, Never>] = [:]

    /// Client-side ceiling on one run. The server's own ceiling is 200k tokens /
    /// $1.50, which in wall-clock terms is well inside this; the reason a client
    /// bound is needed at all is that `SSEParser` drops `:` keep-alive comments
    /// (SSEParser.swift:43), so a server that keeps the connection warm without
    /// emitting an event resets URLSession's idle timer forever and would leave the
    /// agent columns spinning with no error. Cancelling here reaches the seal below,
    /// which turns it into a visible `stream_lost`.
    static let vcRunDeadlineNanos: UInt64 = 240 * 1_000_000_000

    init(loader: @escaping (String) async -> CompanyState = CompanyData.load,
         saver: @escaping (String, CompanyBrief) async -> Bool = CompanyData.saveBrief,
         roadmapFetcher: @escaping (CompanyBrief, AppLanguage) async -> [RoadmapTask] = CompanyData.fetchRoadmap,
         tasksSaver: @escaping (String, [RoadmapTask]) async -> Bool = CompanyData.saveTasks,
         chatSender: @escaping (CompanyChatRequest) async -> CompanyChatReply? = CompanyChatClient.send,
         chatStreamer: @escaping (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { CompanyChatClient.sendStream($0) },
         vcRunner: ((VirtualCompanyRequest) -> AsyncThrowingStream<VirtualCompanyEvent, Error>)? = nil,
         taskRunner: @escaping (RunTaskRequest) async -> RunTaskResponse? = RunTaskClient.run,
         librarySaver: @escaping (String, [Deliverable]) async -> Bool = CompanyData.saveLibrary,
         toolsSaver: @escaping (String, [String]) async -> Bool = CompanyData.saveEnabledTools,
         companionSaver: @escaping (String, String) async -> Bool = CompanyData.saveCompanionId,
         founderPrefsSaver: @escaping (String, FounderPrefs) async -> Bool = CompanyData.saveFounderPrefs,
         introSeenSaver: @escaping (String, Date) async -> Bool = CompanyData.saveIntroSeen,
         enricher: @escaping (CompanyBrief) async throws -> CompanyBrief = { try await ReflectionAPIClient().enrichBrief($0) },
         decisionsSaver: @escaping (String, [DecisionEntry]) async -> Bool = CompanyData.saveDecisions,
         decisionExtractor: @escaping (ApprovedDeliverableDTO, [DecisionEntry]) async -> [ExtractedDecision] = DecisionsClient.extract,
         // Defaulted in the init BODY, same reason as `vcRunner`: the real one closes
         // over `UserDefaults.standard`, and forming it in the nonisolated
         // default-argument context is what makes such defaults warn.
         vcInterviewFlag: VirtualCompanyInterviewFlag? = nil,
         // Defaulted in the init BODY for the same reason as `vcRunner`: the real one
         // touches the `@MainActor` `PetMemoryStore.shared`, which a nonisolated
         // default-argument context cannot reference.
         codingMemoryGate: ((Bool) -> Void)? = nil) {
        self.loader = loader
        self.saver = saver
        self.roadmapFetcher = roadmapFetcher
        self.tasksSaver = tasksSaver
        self.chatSender = chatSender
        self.chatStreamer = chatStreamer
        self.vcRunner = vcRunner ?? { VirtualCompanyClient.run($0) }
        self.taskRunner = taskRunner
        self.librarySaver = librarySaver
        self.toolsSaver = toolsSaver
        self.companionSaver = companionSaver
        self.founderPrefsSaver = founderPrefsSaver
        self.introSeenSaver = introSeenSaver
        self.enricher = enricher
        self.decisionsSaver = decisionsSaver
        self.decisionExtractor = decisionExtractor
        self.vcInterviewFlag = vcInterviewFlag ?? VirtualCompanyInterviewFlag()
        self.codingMemoryGate = codingMemoryGate ?? { PetMemoryStore.shared.setMemoryEnabled($0) }
    }

    func select(_ view: AppView) { self.view = view }

    var isSettingsOpen: Bool { settingsSection != nil }

    /// Open settings, optionally on a specific section (chat cards deep-link this way).
    func openSettings(_ section: SettingsSection = .preferences) {
        settingsSection = section
    }

    func closeSettings() { settingsSection = nil }

    /// Mirrors the web (`Boolean(onboardedAt) || Object.keys(brief).length > 0`):
    /// onboard only when there is no stamp AND the brief has no signal at all.
    var needsOnboarding: Bool {
        company.onboardedAt == nil && !company.brief.hasAnySignal
    }

    /// Hydrate the company from Firestore (fail-soft inside the loader).
    func hydrate(companyId: String) async {
        hydrationToken &+= 1
        let token = hydrationToken
        // Chat is per-account + session-only. An actual account change clears it
        // (and any stuck typing); a same-user re-hydrate (token refresh/reconnect)
        // preserves the in-flight conversation.
        if self.companyId != companyId {
            chatMessages = []
            threads = []
            activeThreadId = nil
            isCompanionTyping = false
            isStreaming = false
            runningTaskIds = []
            activeAgentRuns = []
            isFanningOut = false
            runError = nil
        }
        self.companyId = companyId
        // Re-derived from THIS company's flag on every hydrate, so signing in as
        // someone else never inherits the previous founder's asked-ness (and never
        // re-asks a founder who already answered or skipped). Read synchronously and
        // idempotently, so it needs no `hydrationToken` guard.
        vcInterviewAsked = vcInterviewFlag.wasAsked(companyId)
        isHydrating = true
        let loaded = await loader(companyId)
        guard token == hydrationToken else { return }  // a newer hydrate/reset superseded us
        company = loaded
        // An in-flight prefs write belongs to the OUTGOING account (its own post-await guard
        // drops its commit); leaving its intent here would compose the previous founder's
        // half-written preferences onto this one's next settings change.
        pendingFounderPrefs = nil
        isHydrating = false
        isOnboarding = needsOnboarding
        onboardingToken = hydrationToken
        // The incoming founder's memory switch has to reach `PetMemoryStore` here: it is
        // read statically by the summarize enrichers, so without this push the previous
        // account's answer would keep governing this account's payloads.
        codingMemoryGate(loaded.founderPrefs.memoryEnabled)
    }

    /// Persist + stamp + leave onboarding. (Enrichment happens earlier, in
    /// scaffoldFromOnboarding for the first-run path, or in the Settings model.)
    /// Fail-soft: a failed cloud write still lets the founder into the app.
    /// `token` is `onboardingToken` captured by the caller BEFORE the enrich await;
    /// if an account switch superseded this onboarding (bumping the token) before or
    /// during the save await, discard without writing the wrong doc or clobbering state.
    func finishOnboarding(brief: CompanyBrief, token: Int, language: AppLanguage = .en) async {
        guard token == hydrationToken, let cid = companyId else { return }
        _ = await saver(cid, brief)
        guard token == hydrationToken else { return }
        company.brief = brief
        company.onboardedAt = Date()
        isOnboarding = false
    }

    /// Seed byte's first-run greeting (name + best first move + optional inline action)
    /// as one companion message. Called once, at the onboarding→app edge.
    private func seedFirstRunGreeting(language: AppLanguage) {
        guard companyId != nil else { return }
        let next = RoadmapEngine.nextStep(company.tasks)
        let g = FirstRunGreetingBuilder.build(brief: company.brief, nextStep: next, language: language)
        chatMessages.append(CopilotMessage(role: .companion, text: g.text, firstRunAction: g.action))
    }

    /// First-run only: after the brief is saved + stamped, ask the ≤3 plan-shaping
    /// questions the onboarding brief is missing (goal / traction / problem), one at
    /// a time. A full brief means no gaps → caller falls through to the greeting.
    /// Returns true when an interview was started (so the caller skips the greeting).
    ///
    /// `internal`, not `private`, purely so a test can put a first-run interview in
    /// flight — the flow it belongs to has no live caller today (the dock opens on the
    /// landing hero instead, see `CompanyStoreFirstRunGreetingTests`) and it is owned
    /// by another engineer, so `VirtualCompanyInterviewTests` cannot reach it any other
    /// way. Behaviour is unchanged and the visibility stays module-only.
    func startEnrichInterviewIfNeeded(language: AppLanguage) -> Bool {
        guard companyId != nil else { return false }
        let gaps = EnrichInterview.detectGaps(company.brief)
        guard !gaps.isEmpty else { return false }
        interviewState = (gaps: gaps, idx: 0, seedGreetingWhenDone: true)
        askInterviewGap(gaps[0], language: language)
        return true
    }

    /// Append one interview question as a companion message carrying its gap. The
    /// message text is the question itself, so once answered the card collapses to a
    /// plain bubble showing that question (matches the web `answered` branch).
    private func askInterviewGap(_ gap: InterviewGap, language: AppLanguage) {
        let q = EnrichInterview.question(for: gap, language: language)
        chatMessages.append(CopilotMessage(role: .companion, text: q.ask, interview: gap))
    }

    /// Answer (or skip) the current interview question. A non-blank answer is saved
    /// RAW (trimmed, no distillation) into the brief field and persisted via the
    /// existing saver — durable on mid-interview drop-off. Blank/nil = skip: advance
    /// without saving. Then ask the next gap, or hand off to the first-run greeting.
    func answerInterview(messageId: String, gap: InterviewGap, answer: String?, language: AppLanguage) async {
        guard let i = chatMessages.firstIndex(where: { $0.id == messageId }),
              !chatMessages[i].interviewAnswered else { return }
        chatMessages[i].interviewAnswered = true

        let trimmed = (answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            // Echo the founder's answer as their own chat bubble (matches web),
            // so their input stays visible instead of vanishing on send.
            chatMessages.append(CopilotMessage(role: .me, text: trimmed))
        }
        if !trimmed.isEmpty, let cid = companyId {
            switch gap {
            case .goal: company.brief.goal = trimmed
            case .traction: company.brief.traction = trimmed
            case .problem: company.brief.problem = trimmed
            case .runway: company.brief.runway = trimmed
            case .constraints: company.brief.constraints = trimmed
            }
            _ = await saver(cid, company.brief)
            guard companyId == cid else { return }  // account switched mid-await → bail
        }

        guard var st = interviewState else { return }
        st.idx += 1
        if st.idx < st.gaps.count {
            interviewState = st
            askInterviewGap(st.gaps[st.idx], language: language)
        } else {
            interviewState = nil
            // Only the first-run interview earns the greeting. Welcoming the founder
            // right after a mid-session runway question would read as amnesia.
            if st.seedGreetingWhenDone {
                seedFirstRunGreeting(language: language)
            } else {
                seedVirtualCompanyInterviewClose(language: language)
            }
        }
    }

    /// Closes the Virtual Company's runway/constraints interview.
    ///
    /// Without this the founder answered two questions and the conversation simply
    /// stopped — nothing said, nothing visibly changed. It read as "that did
    /// nothing", which was fair: neither answer appears anywhere in the UI, so a
    /// closing line is the only evidence they landed at all.
    ///
    /// It quotes both answers back rather than thanking them abstractly, because
    /// the point is to show the room heard the specifics, and it names what the
    /// answers change — a founder has no way to know that runway is what makes a
    /// three-week proposal unacceptable.
    private func seedVirtualCompanyInterviewClose(language: AppLanguage) {
        let runway = (company.brief.runway ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let limits = (company.brief.constraints ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Both skipped: say so honestly instead of claiming an effect that is not
        // there. The room will keep saying what it does not know.
        guard !runway.isEmpty || !limits.isEmpty else {
            chatMessages.append(CopilotMessage(role: .companion, text: language == .vi
                ? "Không sao — mình vẫn họp được, chỉ là các khuyến nghị sẽ chung chung hơn vì phòng họp chưa biết runway và ràng buộc của bạn."
                : "No problem — the room can still meet, but its recommendations stay more general while it doesn't know your runway or your constraints."))
            return
        }

        var recorded: [String] = []
        if !runway.isEmpty { recorded.append((language == .vi ? "runway: " : "runway: ") + runway) }
        if !limits.isEmpty { recorded.append(limits.joined(separator: " · ")) }
        let echo = recorded.joined(separator: " · ")

        let effect = language == .vi
            ? "Từ giờ phòng họp cân cả hai khi ra khuyến nghị: nó sẽ loại những đề xuất ăn quá nhiều thời gian bạn còn, và không đề xuất thứ bạn đã gạt."
            : "From now on the room weighs both when it recommends: it drops proposals that eat too much of the time you have left, and stops suggesting what you have already ruled out."

        chatMessages.append(CopilotMessage(
            role: .companion,
            text: (language == .vi ? "Ghi lại rồi — " : "On record — ") + echo + ". " + effect))
    }

    /// Skip: stamp with the current (empty) brief so they aren't re-blocked. Called
    /// directly from the view (no prior await); capture the token at entry and re-check
    /// after the save await.
    func skipOnboarding() async {
        let token = hydrationToken
        guard let cid = companyId else { return }
        _ = await saver(cid, company.brief)
        guard token == hydrationToken else { return }
        company.onboardedAt = Date()
        isOnboarding = false
    }

    /// Generate the roadmap (fail-open). Token-guarded: an account switch during the
    /// fetch discards. An empty result is "no change" (keeps existing tasks).
    /// Language defaults to `.en` (the onboarding scaffold path is English-only); the
    /// Overview board passes the live UI language.
    func generateRoadmap(language: AppLanguage = .en) async {
        let token = hydrationToken
        isGeneratingRoadmap = true
        defer { if token == hydrationToken { isGeneratingRoadmap = false } }
        let fetched = await roadmapFetcher(company.brief, language)
        guard token == hydrationToken, !fetched.isEmpty else { return }
        company.tasks = fetched
        if let cid = companyId { _ = await tasksSaver(cid, fetched) }
    }

    /// First-run scaffold: persist the collected brief, then run the fail-open
    /// roadmap generation — WITHOUT leaving onboarding (the wizard's reveal step
    /// renders next). Token-guarded like finishOnboarding: an account switch
    /// during the persist/scaffold awaits discards (returns .empty), so one
    /// account's brief/tasks can't land under another's doc. Mirrors the web's
    /// scaffoldFromOnboarding; the reveal is derived from the resulting tasks.
    func scaffoldFromOnboarding(brief: CompanyBrief, token: Int) async -> OnboardingReveal {
        guard token == hydrationToken, !Task.isCancelled, let cid = companyId else { return .empty }
        // Enrich (fail-open, mirrors web /api/scaffold): fill summary/audience/etc
        // before planning so a founder who skipped optional fields still gets a
        // full roadmap. A throw/timeout falls back to the raw brief.
        let enriched = (try? await enricher(brief)) ?? brief
        guard token == hydrationToken, !Task.isCancelled else { return .empty }
        _ = await saver(cid, enriched)
        // Cancellation guard: a Skip during the in-flight scaffold cancels this task,
        // so we bail before mutating brief/tasks (skip's empty write is the winner).
        guard token == hydrationToken, !Task.isCancelled else { return .empty }
        company.brief = enriched
        await generateRoadmap()
        guard token == hydrationToken, !Task.isCancelled else { return .empty }
        return OnboardingReveal.build(tasks: company.tasks)
    }

    /// Flip a task's done state and persist (fail-soft).
    func toggleTaskDone(id: String) async {
        guard let i = company.tasks.firstIndex(where: { $0.id == id }) else { return }
        company.tasks[i].done.toggle()
        if let cid = companyId { _ = await tasksSaver(cid, company.tasks) }
    }

    /// Send a founder-typed message to the company companion. Trims + validates,
    /// then either routes to the local coding agent (Engineering department chip +
    /// a linked project — see `EditCodeRouting`) or hands off to `sendMessage` (the
    /// shared streamed-send core — see its doc comment for the full flow, fallback,
    /// and token-guard semantics). `department` defaults to nil so existing callers
    /// (`sendChat(x, language: y)`) keep compiling unchanged.
    ///
    /// This is also the ONLY entry point that convenes the Virtual Company (design §1:
    /// the trigger is what the founder types into chat). The core `sendMessage` must not
    /// fan out on its own, or `walkThroughTask`'s synthesised "walk me through it" ask
    /// would convene the room and the founder's step-by-step guidance could be answered
    /// with a meeting instead.
    ///
    /// `founderAsk` is the founder's own words BEFORE `ChatMode` shaping. `.plan`/`.build`
    /// prepend their intent ("Help me plan this — give me the concrete next steps: …"),
    /// which byte should see — it is what the founder chose — but the router should not:
    /// it decides `request_type` and rewrites the question into `real_question`, so the
    /// mode's framing would bias both. Defaults to the shaped text for callers that do
    /// no shaping.
    func sendChat(_ raw: String, language: AppLanguage, department: Department? = nil,
                  founderAsk: String? = nil) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if EditCodeRouting.shouldRoute(department: department, projectLinked: activeProjectLink != nil) {
            startCodeRun(ask: text)   // echoes the ask, anchors, and proposes the run
            dockCollapsed = false     // reveal the dock (no `.chat` destination on main)
            return
        }
        let ask = (founderAsk ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
        await sendMessage(text, language: language, department: department,
                          convene: ask.isEmpty ? text : ask)
    }

    /// Link a local project folder for the coding agent. Optionally seeds CLAUDE.md
    /// from the brief/decisions (never clobbers an existing one), then probes.
    ///
    /// The seed honours `memoryEnabled` too: CLAUDE.md is standing context the coding agent
    /// reads on every run, so writing the facts on record into it is the most durable USE of
    /// memory there is — and it leaves them sitting in a file on disk, where a founder who
    /// turned memory off would be right to be surprised to find them. With memory off the
    /// seed carries the brief only.
    @discardableResult
    func linkProject(path: String, bootstrapClaudeMd: Bool) -> ProjectLink {
        var link = ProjectProbe.probe(path: path)
        if bootstrapClaudeMd && !link.hasClaudeMd {
            let seed = ClaudeMdBootstrap.compose(brief: company.brief,
                                                 decisions: claudeMdSeedDecisions)
            try? seed.write(to: ProjectProbe.claudeMdURL(forProjectAt: path), atomically: true, encoding: .utf8)
            link = ProjectProbe.probe(path: path)
        }
        if let data = try? URL(fileURLWithPath: path)
            .bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: Self.activeProjectBookmarkKey)
        }
        activeProjectLink = link
        return link
    }

    /// What the CLAUDE.md seed is allowed to say about the facts on record — the gate above,
    /// lifted out of `linkProject` so it is provable without a real folder, a real write, or a
    /// security-scoped bookmark. Empty while the founder has memory off.
    var claudeMdSeedDecisions: [DecisionEntry] {
        company.founderPrefs.memoryEnabled ? company.decisions : []
    }

    /// The specialist companion to bring in for this turn, if a department is in
    /// focus — from the explicit chip, else a department named in the text. Returns
    /// nil when no department applies, it has no mapped companion, or it maps to the
    /// current host companion (no visible handoff needed).
    private func actingSpecialist(text: String, department: Department?) -> (companionId: String, deptName: String)? {
        let deptKey = department?.key ?? DepartmentCompanions.mentionedDeptKey(in: text)
        guard let deptKey, let dept = DepartmentCatalog.find(deptKey),
              let companionId = DepartmentCompanions.companionId(for: deptKey),
              companionId != company.companionId else { return nil }
        return (companionId, dept.name)
    }

    /// Chat-triggered code run: show the founder's ask as a normal message, anchor the
    /// run card to it, and stage the run. With no linked project the coordinator lands
    /// in `.noProject` and the card offers "Link a project".
    func startCodeRun(ask: String) {
        let trimmed = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let msg = CopilotMessage(role: .me, text: trimmed)
        chatMessages.append(msg)
        codingRunAnchorId = msg.id
        codingRun.propose(ask: trimmed, plannedFiles: 2, needsBash: false, link: activeProjectLink)
    }

    // MARK: - Chat threads (session-only, Level 1 — no persistence, no summarization)

    /// Flush the working buffer (`chatMessages`) into its `ChatThread` entry —
    /// creating the entry (and `activeThreadId`, if unset) lazily on its first
    /// non-empty flush, deriving a title once while still untitled, and bumping
    /// `updatedAt` so the thread list re-sorts to the top. A no-op on an empty
    /// buffer: an as-yet-unused "new chat" never appears in the thread list.
    private func flushActiveThread() {
        guard !chatMessages.isEmpty else { return }
        let id = activeThreadId ?? UUID().uuidString
        activeThreadId = id
        let now = Date()
        if let i = threads.firstIndex(where: { $0.id == id }) {
            threads[i].messages = chatMessages
            threads[i].updatedAt = now
            if threads[i].title == nil { threads[i].title = deriveThreadTitle(chatMessages) }
        } else {
            threads.append(ChatThread(id: id, title: deriveThreadTitle(chatMessages),
                                       messages: chatMessages, createdAt: now, updatedAt: now))
        }
    }

    /// Start a fresh, empty conversation: flush the outgoing thread (if it ever
    /// held anything), then point the working buffer at a brand-new id. The new
    /// thread doesn't appear in `threads` until it actually holds a message (the
    /// next flush creates it) — mirrors the web, where an unused "new chat" isn't
    /// a real row in the history list either.
    ///
    /// No-op while a chat turn is in flight (`isStreaming`/`isCompanionTyping`):
    /// `sendMessage` streams `.delta`s and appends `.done` chips straight into
    /// `chatMessages` by id, so repointing the buffer mid-turn would silently
    /// drop the in-flight reply (delta lookups fail against the new buffer) and
    /// leak its `.done` chips into whatever thread became active. This is
    /// defense in depth — `CopilotChatView` also disables the controls that
    /// call these while streaming — so a stream survives even if some other
    /// caller bypasses the UI.
    func newChat() {
        guard !isStreaming, !isCompanionTyping else { return }
        flushActiveThread()
        activeThreadId = UUID().uuidString
        chatMessages = []
        // A run anchored in (or floating at the bottom of) the outgoing thread must
        // not leak into this fresh, empty one — clear it (no-op while running).
        codingRunAnchorId = nil
        codingRun.cancel()
    }

    /// Switch the working buffer to a different thread: flush the outgoing one,
    /// then load the target's messages. Switching to the thread already active
    /// is a no-op (would otherwise round-trip the buffer through itself).
    ///
    /// Also a no-op while a chat turn is in flight — see `newChat()`'s doc
    /// comment for why repointing `chatMessages` mid-stream corrupts state.
    func switchThread(_ id: String) {
        guard !isStreaming, !isCompanionTyping else { return }
        guard id != activeThreadId else { return }
        flushActiveThread()
        activeThreadId = id
        chatMessages = threads.first(where: { $0.id == id })?.messages ?? []
        // A run anchored in the outgoing thread must not float to the bottom of
        // the incoming one — clear it (no-op while running).
        codingRunAnchorId = nil
        codingRun.cancel()
    }

    /// Rename a thread. A blank/whitespace-only title clears back to nil — the
    /// view shows "New chat" for that same nil, re-deriving from the thread's
    /// first message the next time it would matter (deriving again is harmless:
    /// `flushActiveThread` only sets a title while it's nil).
    func renameThread(_ id: String, title: String) {
        guard let i = threads.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        threads[i].title = trimmed.isEmpty ? nil : trimmed
    }

    /// Delete a thread. Deleting a non-active thread just removes it. Deleting
    /// the ACTIVE thread falls back to the most-recently-updated remaining
    /// thread (loading its messages into the buffer); with nothing left, opens
    /// a fresh new chat — `chatMessages` is cleared FIRST so `newChat()`'s
    /// flush has nothing to (wrongly) resurrect from the just-deleted thread.
    ///
    /// No-op while a chat turn is in flight — gated for consistency with
    /// `newChat()`/`switchThread(_:)` even though deleting a non-active thread
    /// alone wouldn't repoint `chatMessages`: deleting the ACTIVE thread mid-
    /// stream would, via the fallback/`newChat()` branches below.
    func deleteThread(_ id: String) {
        guard !isStreaming, !isCompanionTyping else { return }
        threads.removeAll { $0.id == id }
        guard id == activeThreadId else { return }
        if let fallback = pickFallbackThreadId(after: id, in: threads) {
            activeThreadId = fallback
            chatMessages = threads.first(where: { $0.id == fallback })?.messages ?? []
            // A run anchored in the just-deleted active thread must not float to
            // the bottom of the fallback one — clear it (no-op while running).
            codingRunAnchorId = nil
            codingRun.cancel()
        } else {
            chatMessages = []
            newChat()   // newChat() already clears codingRunAnchorId/codingRun
        }
    }

    /// Founder taps "Walk me through it" on a `.you` task (department card / Tasks
    /// board `yourMove` card / roadmap-map `needsYou` node) — byte can't run these,
    /// so instead of `runTask` (which would fabricate a deliverable) this composes a
    /// natural founder ask for step-by-step guidance and routes it through the SAME
    /// grounded chat-send path as a typed message: the reply is streamed and grounded
    /// on the department summary + prior work (via `ChatContext.compose`), so the
    /// guidance is specific to this task, not generic. `taskRunner` is never touched.
    func walkThroughTask(_ task: RoadmapTask, language: AppLanguage) async {
        await sendMessage(Self.walkThroughMessage(for: task, language: language), language: language)
    }

    /// Compose the founder's ask for `walkThroughTask` — mirrors how a founder would
    /// type it themselves, so it reads as a normal chat turn (not a special command).
    private static func walkThroughMessage(for task: RoadmapTask, language: AppLanguage) -> String {
        let detail = task.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        switch language {
        case .vi:
            var msg = "Hướng dẫn mình tự làm việc này: \(task.title)."
            if !detail.isEmpty { msg += " \(detail)" }
            return msg
        case .en:
            var msg = "Walk me through how to do this myself: \(task.title)."
            if !detail.isEmpty { msg += " \(detail)" }
            return msg
        }
    }

    /// Core of a chat send: append the founder's message, stream a grounded companion
    /// reply (fallback to the non-streaming client), and handle any `run_task_id` the
    /// reply carries. Shared by `sendChat` (typed founder text) and `walkThroughTask`
    /// (composed guidance ask) — both are ordinary chat turns from byte's point of
    /// view, differing only in what text is sent. `text` is assumed non-empty/trimmed
    /// by the caller. Session-only. Token-guarded throughout: an account switch at
    /// any await point (mid-stream or mid-fallback-reply) discards this send's
    /// remaining work — hydrate/reset already cleared chat + typing for a real
    /// switch, so a stale write is silently dropped rather than landing in the new
    /// account's conversation.
    ///
    /// Flow: append the user message, append an EMPTY companion placeholder (stable
    /// id), flip `isStreaming` on, then consume `chatStreamer`. Each `.delta` is
    /// appended into the placeholder in place (found by id) — `isCompanionTyping`
    /// flips off on the first token, mirroring `SessionChatController`'s
    /// typing→streaming transition, while `isStreaming` stays true for the WHOLE
    /// send (stream + any fallback) so the UI can keep Send disabled the entire
    /// time. `.done` is a no-op: the placeholder already holds the full text.
    ///
    /// Fallback (REQUIRED for deploy-order safety): if the stream throws — network
    /// failure, a non-200, an `event: error` frame, a typed `CompanyChatStreamError`
    /// — OR it finishes clean but yielded no text at all (the shape the live CF
    /// collapses to pre-deploy: a plain JSON body with no `event:`/`data:` lines
    /// parses to zero SSE frames, so the stream just ends with nothing yielded),
    /// fall back to the existing non-streaming `chatSender(req)` and fill the SAME
    /// placeholder — preserving every existing semantic: the offline copy, the
    /// runTaskId/draft-run chaining, and the account guard.
    ///
    /// `convene` is the question to put to the Virtual Company, or nil for "do not
    /// convene". Only `sendChat` passes it: a synthesised ask (`walkThroughTask`) is not
    /// a founder deciding something, and answering "walk me through how to do this
    /// myself" with a meeting is a worse answer than the guidance that was asked for.
    private func sendMessage(_ text: String, language: AppLanguage, department: Department? = nil,
                             convene: String? = nil) async {
        guard !isCompanionTyping, !isStreaming else { return }
        chatMessages.append(CopilotMessage(role: .me, text: text))
        isCompanionTyping = true
        let history = chatMessages.dropLast().suffix(20).map {
            ChatTurnDTO(role: $0.role == .me ? "me" : "companion", text: $0.text)
        }
        let cid = companyId
        // Tasks byte is allowed to run this turn — mirrors the web's openTasks
        // filter (codepetCanDo == not done, not already drafted, deps satisfied,
        // not a founder-only task). Capped so the payload stays small.
        let runnable = company.tasks
            .filter { RoadmapEngine.status(for: $0, in: company.tasks) == .codepetCanDo }
            .prefix(60)
            .map { RunnableRef(id: $0.id, title: $0.title) }
        // The currently-OFF toolkit items — lets the CF decide whether to
        // suggest turning one on (`setup` in the reply).
        let envSetup = Toolkit.catalog
            .filter { !company.enabledTools.contains($0.id) }
            .map { SetupItemDTO(category: $0.category.rawValue, name: $0.name, why: $0.why) }
        // The other half: the skills that are ON. Without this the CF could only
        // ever be told what to offer, never what the founder already chose.
        let enabledSkills = Toolkit.enabledSkillIds(in: company.enabledTools)
        let req = CompanyChatRequest(
            companyId: companyId, language: language.rawValue, companionId: company.companionId,
            // `memoryEnabled` off drops the decisions block: a fact the founder forgot in
            // the Memory panel must not come back through grounding.
            context: ChatContext.compose(brief: company.brief, tasks: company.tasks, decisions: company.decisions,
                                          library: company.library, query: text, focusDepartment: department,
                                          memoryEnabled: company.founderPrefs.memoryEnabled),
            history: Array(history), userMessage: text, runnable: Array(runnable), envSetup: envSetup,
            // nil at defaults, so an untouched settings panel adds nothing to the wire
            // and nothing to the prompt.
            styleFragment: company.founderPrefs.style.promptFragment(),
            enabledSkills: enabledSkills)

        // Department handoff: if a specialist leads this turn (chip focus or a
        // department named in the text), the reply is spoken by that specialist
        // directly — its "Name · Dept" header conveys the handoff.
        let specialist = actingSpecialist(text: text, department: department)

        let placeholderId = UUID().uuidString
        chatMessages.append(CopilotMessage(id: placeholderId, role: .companion, text: "",
                                            companionId: specialist?.companionId, deptName: specialist?.deptName))
        isStreaming = true

        // Fan-out: the room is convened by the router's escape hatch, not by a
        // client-side heuristic. Both calls go out at once so ordinary chat keeps
        // its current latency — running intake first would put ~2s in front of
        // every message, including "hi". `convene` is nil for a synthesised ask, and
        // carries the founder's own words (pre-`ChatMode` shaping) for a typed one.
        if let convene {
            startVirtualCompanyRun(ask: convene, anchorId: placeholderId,
                                   cid: cid, language: language)
        }

        var streamedText = ""
        var streamThrew = false
        var receivedDone = false
        // The `.done` frame's actions, CAPTURED here and dispatched below — after the
        // tail has written this reply's text. Dispatching from inside the loop (the
        // shape this shipped with) ran every action against a bubble that was still
        // empty, which broke both halves of an action's contract: `inlineActionTarget`
        // rejects an empty reply, so a nav/setup chip fell to its standalone-row
        // fallback and drew detached from the reply it belongs to; and a run's whole
        // execute-log played out before the lead-in announcing it was written. The
        // non-streaming fallback below always had this order right — now both paths
        // share it.
        var doneAction: ChatDoneAction?
        do {
            for try await event in chatStreamer(req) {
                // Checked before touching state on every event: a switch mid-stream
                // must bail before writing into the (already-reset) new account.
                guard companyId == cid else { return }
                switch event {
                case .delta(let chunk):
                    if isCompanionTyping { isCompanionTyping = false }
                    streamedText += chunk
                    if let i = chatMessages.firstIndex(where: { $0.id == placeholderId }) {
                        chatMessages[i].text = streamedText
                    }
                case .done(_, _, let action):
                    // Streaming is now the common success path, so run_task_id
                    // (and nav/setup/remember) handling must fire here too —
                    // not just in the fallback below (previously the only
                    // place run_task_id ran, back when streaming usually
                    // failed pre-deploy). Captured rather than dispatched: the
                    // reply's own text is written by the tail, and every action
                    // belongs to a reply that has already spoken.
                    receivedDone = true
                    doneAction = action
                }
            }
        } catch {
            streamThrew = true
        }
        guard companyId == cid else { return }

        // Gate the fallback on "no `.done` frame was received", NOT on empty
        // text: byte can legitimately reply with only a run-task decision and
        // no chat text (zero deltas, then `.done(runTaskId:)`). Falling back
        // on empty text there would fire a SECOND chatSender call and run
        // handleRunTaskId AGAIN for the same task — a duplicate CF call and a
        // duplicate draft card. A well-formed `.done` (even empty-text)
        // means the stream succeeded, so no fallback. The pre-deploy safety
        // net still works: a plain-JSON (non-SSE) response parses to zero
        // frames, so `.done` never fires and `!receivedDone` is true.
        // The decision itself lives in `ChatTailAction` (a testable value type); this
        // only carries it out. The room is no longer part of this decision: it owns its
        // own appended message, so byte's turn ends exactly as it did before the feature.
        switch ChatTailAction.decide(streamThrew: streamThrew, receivedDone: receivedDone,
                                     streamedText: streamedText, action: doneAction) {
        case .fallback:
            let reply = await chatSender(req)
            guard companyId == cid else { return }
            let offline = language == .vi
                ? "Mình không kết nối được lúc này — thử lại sau nhé."
                : "I can't reach my brain right now — try again in a bit."
            if let i = chatMessages.firstIndex(where: { $0.id == placeholderId }) {
                chatMessages[i].text = reply?.text ?? offline
            }
            let action = ChatDoneAction(runTaskId: reply?.runTaskId, nav: reply?.nav,
                                         setup: reply?.setup, remember: reply?.remember ?? [])
            await handleDoneAction(action, cid: cid, language: language)
            guard companyId == cid else { return }
        case .leadIn(let kind):
            // A `.done` was received but byte sent zero chat text — don't leave the
            // placeholder blank. WHICH line depends on what came back: only a run is
            // work being started (see `ChatTailAction.LeadIn`).
            if let i = chatMessages.firstIndex(where: { $0.id == placeholderId }) {
                chatMessages[i].text = Self.leadInCopy(kind, language: language)
            }
        case .none:
            break
        }
        // Dispatched HERE, not from the `.done` case above: the reply now carries its
        // text (streamed or lead-in), so a chip attaches to it instead of appending a
        // detached row, and a run announces itself before it starts. `.fallback` has
        // already dispatched its own action and left this nil.
        if let doneAction {
            await handleDoneAction(doneAction, cid: cid, language: language)
            guard companyId == cid else { return }
        }
        // The run is NOT awaited. It writes into its own appended message, so it has
        // no claim on byte's turn: byte's typing dots clear, Send/New chat/switch/delete
        // re-enable, and this tail is byte-for-byte the no-feature tail. A run that is
        // still going (or has not even routed yet) simply arrives later, which is a new
        // message rather than a rewrite of an answer the founder has already read.
        isCompanionTyping = false
        isStreaming = false
        // Flush this turn into its thread — bumps `updatedAt` (re-sorts the thread
        // list) and, on the very first turn, derives the thread's title + mints
        // its id. Every early `return` above only fires on an account switch,
        // where hydrate() already reset chatMessages/threads for the new account —
        // nothing stale to flush there.
        flushActiveThread()
    }

    // MARK: - Virtual Company fan-out

    /// Start a Virtual Company run for `ask`, anchored to byte's message for this turn.
    /// Never awaited by the caller — see `publishRunProgress` for why the room owns its
    /// own appended message, and `vcTasks`/`vcRunDeadlineNanos` for what bounds it.
    private func startVirtualCompanyRun(ask: String, anchorId: String,
                                        cid: String?, language: AppLanguage) {
        let vcRequest = VirtualCompanyRequest(
            request: ask,
            language: language.rawValue,
            founder: FounderContextMapper.founder(from: company.brief),
            stressTest: false)
        // Inherits this method's @MainActor isolation (SWIFT_APPROACHABLE_CONCURRENCY
        // + SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor), so the loop body — and the
        // `chatMessages` writes it makes through `publishRunProgress` — run on the
        // main actor with no hop and no `MainActor.run` wrapper. The network itself
        // never blocks the actor: `vcRunner` does its I/O in a `Task.detached` and
        // this loop only suspends waiting on the stream.
        let vcRunner = self.vcRunner
        // The room's OWN message, minted here so every frame addresses the same
        // appended message. Nothing is appended until the router says `multi_agent`.
        let roomMessageId = UUID().uuidString
        let vcTask = Task { [weak self] () -> Void in
            var state = VirtualCompanyRunState()
            do {
                for try await event in vcRunner(vcRequest) {
                    state.apply(event)
                    // The escape hatch fired: discard the run and let chat be.
                    // The founder never learns a routing decision happened.
                    if state.isEscapeHatch { break }
                    guard let self else { return }
                    await self.publishRunProgress(state, roomMessageId: roomMessageId,
                                                  anchorId: anchorId, cid: cid, language: language)
                }
            } catch {
                // A failed run must never damage the chat (spec §7). 503 is the kill
                // switch and 429 the daily cap — both are silent to the FOUNDER by
                // design, but not to the log: a live kill switch, an expired token and
                // a broken client were previously indistinguishable from a working
                // feature that never convened anyone.
                Self.logRunFailure(error)
            }
            // Seal a run that died with the room already on screen. A dropped stream, a
            // TLS reset, an idle timeout, the deadline watchdog below, or a server that
            // just stops without a `done` frame all arrive here with the room's cards
            // already rendered, so returning silently would leave the agent columns
            // spinning forever with no error and nothing to retry. `.failed` is excluded
            // because a terminal `error` frame published its own code already.
            if state.handsOffToRoom, state.phase != .finished, state.phase != .failed {
                state.terminalError = "stream_lost"
                state.phase = .failed
                await self?.publishRunProgress(state, roomMessageId: roomMessageId,
                                               anchorId: anchorId, cid: cid, language: language)
            }
            self?.vcTasks[roomMessageId] = nil
        }
        vcTasks[roomMessageId] = vcTask
        // Bound the run (see `vcRunDeadlineNanos`). A no-op once the run has removed
        // its own registry entry, which is every normal ending.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.vcRunDeadlineNanos)
            self?.vcTasks[roomMessageId]?.cancel()
        }
    }

    /// Publishes run progress as the room's OWN companion message: appended once, on
    /// the first `multi_agent` frame, then updated in place as later frames arrive.
    ///
    /// Appended, not written into byte's message (the shape this shipped with first),
    /// for four reasons that all had the same root: the transcript scrolls on
    /// `chatMessages.count`, so a run rendered inside an already-appended message grew
    /// 30–60s of cards below the viewport and never scrolled; byte's turn could not end
    /// normally, so its typing dots stayed pinned under the room's cards; byte's `done`
    /// side effects (roadmap, decisions) ran on a turn the founder had been told was
    /// superseded; and a run that decided after the turn closed rewrote an answer the
    /// founder had already read, which needed a guard of its own. A separate message
    /// removes all four — see the design doc §3.
    ///
    /// Every write is behind `handsOffToRoom`, so a run the router sent elsewhere —
    /// or one that died before routing — cannot touch `chatMessages` at all.
    private func publishRunProgress(_ state: VirtualCompanyRunState,
                                    roomMessageId: String,
                                    anchorId: String,
                                    cid: String?,
                                    language: AppLanguage) async {
        guard companyId == cid, state.handsOffToRoom else { return }
        // The room belongs to the conversation its question was asked in. `anchorId` is
        // byte's message for that turn, so its absence means the founder has moved on
        // (New chat, a thread switch, a delete) and the room must not land in whichever
        // conversation happens to be on screen now. Switching back restores the buffer,
        // and the state published is always the whole run, so nothing is lost by the
        // frames refused in between.
        guard let anchor = chatMessages.firstIndex(where: { $0.id == anchorId }) else { return }
        if let i = chatMessages.firstIndex(where: { $0.id == roomMessageId }) {
            chatMessages[i].vcRun = state
        } else {
            // INSERTED under its own question, not appended. Nothing holds the composer
            // any more, so the founder can complete two more turns while a run is still
            // going: appending would drop "Actually — this one needs the whole room"
            // beneath an unrelated answer, reading as a reply to that instead. Later
            // frames resolve by id, so the position is decided once, here.
            chatMessages.insert(CopilotMessage(id: roomMessageId, role: .companion,
                                               text: Self.handoffLine(language), vcRun: state),
                                at: anchor + 1)
        }
        // Behind every guard above, so a discarded run (escape hatch), a killed run
        // (503/429) or one that died before a brief can never trigger it.
        maybeAskVirtualCompanyInterview(state, language: language)
    }

    /// byte's one line of handoff, spoken above the room's cards. It follows byte's
    /// own complete answer now, so it reads as a second thought rather than a refusal
    /// to answer — the founder sees a companion escalating, not a UI mode switch.
    private static func handoffLine(_ language: AppLanguage) -> String {
        language == .vi
            ? "Thật ra cái này cần cả phòng — để mình gọi product với finance vào."
            : "Actually — this one needs the whole room. Let me bring in product and finance."
    }

    /// One log line per failure mode. Every one of these was previously silent except
    /// 400, so a kill switch (503), an exhausted cap (429), an expired token and a
    /// renamed backend field all looked identical from the outside: a feature that
    /// simply never convened anyone.
    private static func logRunFailure(_ error: Error) {
        switch error as? VirtualCompanyRunError {
        case let .http(status, body):
            print("virtualCompanyRun: HTTP \(status) — \(body?.error ?? "no error field")"
                  + (body?.detail.map { ": \($0)" } ?? ""))
        case .notSignedIn:
            print("virtualCompanyRun: no Firebase ID token — the room cannot run")
        case .malformedResponse:
            print("virtualCompanyRun: malformed response (no HTTPURLResponse)")
        case nil:
            print("virtualCompanyRun: stream failed — \(error)")
        }
    }

    /// Asked at most once per founder. Mirrors `vcInterviewFlag`, which persists it
    /// per company id: `hydrate` re-derives this from the incoming company (so an
    /// account switch never inherits the previous founder's asked-ness) and `reset`
    /// clears it. It cannot be inferred from the brief alone, because skipping is a
    /// no-write path and would otherwise re-ask on every launch, forever.
    @Published private(set) var vcInterviewAsked: Bool = false

    /// Once the room has actually produced a brief, ask for the two facts that make
    /// every run after this one concrete. Reuses the existing interview queue:
    /// `askInterviewGap` owns the card, `answerInterview` owns the reply path.
    private func maybeAskVirtualCompanyInterview(_ state: VirtualCompanyRunState,
                                                 language: AppLanguage) {
        // Never stomp an interview already in flight (the first-run one owns the
        // queue until it empties) — that would lose its remaining gaps AND its
        // greeting tail.
        guard interviewState == nil else { return }
        guard VirtualCompanyInterview.shouldAsk(state: state,
                                                brief: company.brief,
                                                alreadyAsked: vcInterviewAsked) else { return }
        vcInterviewAsked = true
        // Persist BEFORE asking, keyed to this founder. Asking is the commitment —
        // whether they answer or skip, we do not ask again.
        if let cid = companyId { vcInterviewFlag.markAsked(cid) }
        let gaps = VirtualCompanyInterview.gaps
        // seedGreetingWhenDone: false — this interview happens mid-session, long
        // after onboarding. The first-run greeting would read as amnesia.
        interviewState = (gaps: gaps, idx: 0, seedGreetingWhenDone: false)
        askInterviewGap(gaps[0], language: language)
    }

    /// Records the brief as a decision the founder has locked in, which then grounds
    /// chat and run-task through `ChatContext`. Never automatic — the button in the
    /// brief card is the only caller (spec: approve-then-record).
    ///
    /// `async` because decisions do NOT go through `saver` (the brief saver); they go
    /// through `decisionsSaver`, an async closure — same path `handleRemember` and
    /// `rememberFromApproval` use.
    ///
    /// It must SAY something. This is the feature's only call to action, and it used to
    /// persist in silence: no chip, no consumed state, nothing at all when the brief had
    /// no recommendation or the run no id. So it marks the run's message consumed (the
    /// card then reads "locked in" instead of offering the button again) and appends the
    /// same 📌 "Noted" chip `handleRemember` uses for a fact byte recorded on its own —
    /// one affordance for "this is on the record now", not two.
    ///
    /// `messageId` is the run's own message, which is also the idempotency key: a second
    /// tap (or a double-click) does nothing rather than appending a second chip.
    func lockInVirtualCompanyDecision(_ state: VirtualCompanyRunState, messageId: String) async {
        guard let runId = state.runId,
              let extracted = VirtualCompanyDecision.extracted(from: state, runId: runId),
              let i = chatMessages.firstIndex(where: { $0.id == messageId }),
              !chatMessages[i].actionConsumed else { return }
        chatMessages[i].actionConsumed = true
        let cid = companyId
        company.decisions = Decisions.mergeDecisions(existing: company.decisions,
                                                     extracted: [extracted],
                                                     now: Date().timeIntervalSince1970 * 1000)
        chatMessages.append(CopilotMessage(
            role: .companion, text: "",
            noted: [RememberedFact(topic: extracted.topic, statement: extracted.statement)]))
        if let cid { _ = await decisionsSaver(cid, company.decisions) }
    }

    /// The specialist for a task's owning department, if it maps to a companion
    /// other than the host — used to attribute the run's producing row + draft.
    private func taskSpecialist(for task: RoadmapTask) -> (companionId: String, deptName: String)? {
        guard let deptKey = task.dept, let dept = DepartmentCatalog.find(deptKey),
              let companionId = DepartmentCompanions.companionId(for: deptKey),
              companionId != company.companionId else { return nil }
        return (companionId, dept.name)
    }

    /// If byte chose to run a runnable task, produce a draft deliverable inline —
    /// shared by both the streaming `.done` case and the non-streaming fallback,
    /// so a `run_task_id` fires on whichever path yielded it (never both: a
    /// stream that finishes clean and non-empty never reaches the fallback, and
    /// the fallback only runs when the stream threw or yielded no text).
    /// `cid` is the `companyId` captured at the start of `sendChat` — re-checked
    /// after the `taskRunner` await so an account switch mid-run can't append
    /// this account's draft into a different (already-hydrated) account's chat.
    private func handleRunTaskId(_ runId: String?, cid: String?, language: AppLanguage) async {
        // No run was requested — the overwhelmingly common case. Say nothing.
        guard let runId else { return }

        // Everything below is the case where byte ALREADY promised. `sendMessage`
        // writes "on it, putting that together now" before this runs, so returning
        // silently here left the founder watching a promise nobody kept — observed
        // in the app: lead-in, then nothing, forever. Each refusal knows exactly
        // why, and three of the five reasons are the founder's own move rather than
        // a failure, so every one of them is worth saying out loud.
        guard let task = company.tasks.first(where: { $0.id == runId }) else {
            appendRunRefusal(language == .vi
                ? "Mình vừa nói sẽ làm, nhưng không tìm thấy việc đó trong lộ trình nữa — có thể nó đã bị đổi. Bạn nói lại là việc nào nhé."
                : "I said I'd get on it, but I can't find that task in the roadmap any more — it may have changed. Tell me which one and I'll pick it up.")
            return
        }

        let status = RoadmapEngine.status(for: task, in: company.tasks)
        guard status == .codepetCanDo else {
            appendRunRefusal(Self.runRefusalCopy(status, task: task, language: language))
            return
        }
        _ = await produceDraftInline(for: task, cid: cid, language: language)
    }

    private func appendRunRefusal(_ text: String) {
        chatMessages.append(CopilotMessage(role: .companion, text: text))
    }

    /// The line that fills a reply which carried an action but no words of its own. Each
    /// says only what the action it belongs to actually delivers: the chip below it opens
    /// a place or offers a switch, and neither is work being produced. "On it — putting
    /// that together now." is reserved for the one case where something IS being made.
    private static func leadInCopy(_ kind: ChatTailAction.LeadIn, language: AppLanguage) -> String {
        let vi = language == .vi
        switch kind {
        case .run:
            return vi ? "Được rồi — mình chuẩn bị việc đó ngay đây."
                      : "On it — putting that together now."
        case .nav:
            return vi ? "Được rồi — chỗ đó đây, bấm vào là tới."
                      : "Sure — this takes you there."
        case .setup:
            return vi ? "Đây là thứ nên bật cho việc này."
                      : "This is the one to turn on for that."
        case .noted:
            return vi ? "Mình ghi lại rồi." : "Noted."
        case .nothing:
            // A well-formed reply with no words and nothing on offer is a failure, and the
            // founder is owed that rather than a promise. Says nothing about why, because
            // this side of the wire does not know.
            return vi ? "Mình chưa có câu trả lời nào ở đây — bạn nhắc lại giúp mình nhé?"
                      : "I didn't have an answer for that — ask me again?"
        }
    }

    /// Why byte cannot run this task, in the founder's terms. Deliberately names the
    /// task, because the founder did not choose it — byte did — so "that one" is not
    /// enough to act on.
    private static func runRefusalCopy(_ status: TaskStatus,
                                      task: RoadmapTask,
                                      language: AppLanguage) -> String {
        let vi = language == .vi
        switch status {
        case .needsApproval:
            return vi
                ? "\"\(task.title)\" đã có bản nháp đang chờ bạn duyệt — mình không làm lại để khỏi ghi đè. Duyệt hoặc yêu cầu sửa bản đó trước nhé."
                : "\"\(task.title)\" already has a draft waiting for your approval — I won't redo it and overwrite that. Approve or revise the existing one first."
        case .done:
            return vi
                ? "\"\(task.title)\" đã xong rồi — mình không chạy lại. Nếu muốn làm lại từ đầu thì mở việc đó ra rồi nói mình."
                : "\"\(task.title)\" is already done — I won't run it again. Open it and tell me if you want it redone from scratch."
        case .blocked:
            return vi
                ? "\"\(task.title)\" chưa tới lượt — nó còn chờ một việc khác xong, hoặc giai đoạn của nó chưa mở."
                : "\"\(task.title)\" isn't ready yet — it's still waiting on another task, or its phase hasn't opened."
        case .needsYou:
            return vi
                ? "\"\(task.title)\" là việc chỉ bạn làm được, mình không thay bạn làm được việc đó. Cần thì mình hướng dẫn từng bước."
                : "\"\(task.title)\" is yours to do — I can't do that one for you. I can walk you through it step by step if that helps."
        case .codepetCanDo:
            // Unreachable: the caller only lands here when the status is not runnable.
            return vi
                ? "Mình chưa chạy được \"\(task.title)\" lúc này."
                : "I couldn't start \"\(task.title)\" just now."
        }
    }

    /// The single inline-run path shared by EVERY chat run (typed "run" command
    /// AND the greeting's "Do it with me"), so "how the agent works" shows the same
    /// everywhere: a transient producing placeholder drives the execute-log — a
    /// step checklist revealed progressively (transparency, not a snap-to-done) —
    /// attributed to the task's department specialist (pet sprite + "Name · Dept").
    /// The last step stays "working" until BOTH the reveal and the real result
    /// finish, then it collapses into the draft card. Returns true if a draft was
    /// appended (false → an honest "couldn't generate" bubble). Account-guarded
    /// via `cid` so a mid-run account switch can't land in another account's chat.
    @discardableResult
    private func produceDraftInline(for task: RoadmapTask, cid: String?, language: AppLanguage) async -> Bool {
        let specialist = taskSpecialist(for: task)
        let steps = Self.execSteps(task: task, specialist: specialist,
                                   decisionCount: company.decisions.count, language: language)
        let producingId = UUID().uuidString
        chatMessages.append(CopilotMessage(id: producingId, role: .companion, text: task.title, producing: true,
                                           companionId: specialist?.companionId, deptName: specialist?.deptName,
                                           execSteps: steps))
        let reveal = Task { [cid] in
            for idx in 0..<max(0, steps.count - 1) {
                try? await Task.sleep(nanoseconds: Self.execStepNanos)
                guard companyId == cid,
                      let mi = chatMessages.firstIndex(where: { $0.id == producingId }) else { return }
                chatMessages[mi].execSteps?[idx].done = true
            }
        }
        let result = await taskRunner(runRequest(for: task, language: language))
        _ = await reveal.value   // let every revealed step land before finishing
        guard companyId == cid else { return false }
        if let mi = chatMessages.firstIndex(where: { $0.id == producingId }),
           let count = chatMessages[mi].execSteps?.count {
            for i in 0..<count { chatMessages[mi].execSteps?[i].done = true }
        }
        try? await Task.sleep(nanoseconds: Self.execDoneBeatNanos)
        guard companyId == cid else { return false }
        chatMessages.removeAll { $0.id == producingId }
        if let draft = buildDeliverable(from: result, task: task) {
            chatMessages.append(CopilotMessage(role: .companion, text: "", draft: draft,
                                               companionId: specialist?.companionId, deptName: specialist?.deptName))
            // Reflect the run on the roadmap so the task leaves the "next moves" set
            // and can't be re-run into a duplicate draft (mirrors the board runTask).
            if let ti = company.tasks.firstIndex(where: { $0.id == task.id }) {
                // `handleRunTaskId`'s `status == .codepetCanDo` guard ran BEFORE the
                // `taskRunner` await above, so mark-complete ("I already did this") may
                // have set `done = true` on this very task while the run was in flight.
                // Writing `drafted` onto a done task strands the draft forever:
                // `RoadmapEngine.status` short-circuits to `.done` before ever consulting
                // `drafted`, `approveTask` refuses (its own `!done` guard), and the
                // library never receives it — so skip the write when done wins the race.
                if !company.tasks[ti].done {
                    company.tasks[ti].draft = draft
                    company.tasks[ti].drafted = true
                    if let cid { _ = await tasksSaver(cid, company.tasks) }
                }
            }
            return true
        } else {
            chatMessages.append(CopilotMessage(role: .companion, text: language == .vi
                ? "Không tạo được ngay bây giờ — thử lại nhé."
                : "Couldn't generate that just now — try again."))
            return false
        }
    }

    /// Dispatch a `.done` frame's actions — shared by the streaming `.done` case and
    /// the non-streaming JSON fallback. `runTaskId`/`nav`/`setup` are mutually
    /// exclusive (the CF sets ≤1), so at most one of the three branches below does
    /// anything; `remember` is orthogonal and always runs alongside. Each step
    /// re-checks `companyId == cid` (via its own handler) so an account switch
    /// mid-await stops the rest from landing in a different account's chat.
    private func handleDoneAction(_ action: ChatDoneAction, cid: String?, language: AppLanguage) async {
        await handleRunTaskId(action.runTaskId, cid: cid, language: language)
        guard companyId == cid else { return }
        await handleNav(action.nav, cid: cid)
        guard companyId == cid else { return }
        await handleSetup(action.setup, cid: cid)
        guard companyId == cid else { return }
        await handleRemember(action.remember, cid: cid)
    }

    /// `nav`: append a tappable chip (NOT auto-navigate — mirrors the web, which
    /// shows a chip the founder taps). Tapping it later calls `activateNav`.
    /// The reply an inline action belongs to: the last companion message that
    /// actually said something and isn't already carrying a card of its own.
    ///
    /// Actions used to be appended as their own `text: ""` message, which drew the
    /// control as a separate row — outside the reply's bubble and outside the avatar
    /// column it should line up with, wasting the width of the dock. Attaching to
    /// the reply lets the view draw the control inside that reply's card. The append
    /// is kept as a fallback for an action that arrives with no reply to attach to.
    private func inlineActionTarget() -> Int? {
        guard let i = chatMessages.lastIndex(where: { $0.role == .companion }) else { return nil }
        let m = chatMessages[i]
        guard !m.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !m.producing, m.draft == nil, m.vcRun == nil, m.interview == nil else { return nil }
        return i
    }

    private func handleNav(_ nav: NavAction?, cid: String?) async {
        guard let nav, companyId == cid else { return }
        if let i = inlineActionTarget(), chatMessages[i].navChip == nil {
            chatMessages[i].navChip = nav
        } else {
            chatMessages.append(CopilotMessage(role: .companion, text: "", navChip: nav))
        }
    }

    /// `setup`: append a tappable enable-card. Tapping it later calls `activateSetup`
    /// (guarded — never flips an already-on tool off).
    private func handleSetup(_ setup: SetupAction?, cid: String?) async {
        guard let setup, companyId == cid else { return }
        if let i = inlineActionTarget(), chatMessages[i].setupSuggestion == nil {
            chatMessages[i].setupSuggestion = setup
        } else {
            chatMessages.append(CopilotMessage(role: .companion, text: "", setupSuggestion: setup))
        }
    }

    /// `remember`: AUTO-merge + persist immediately (background memory, like the
    /// web) — no approval gate, unlike a draft. Mirrors `rememberFromApproval`'s
    /// merge+persist; appends one transient "Noted" chip per fact so the founder
    /// sees what stuck.
    private func handleRemember(_ facts: [RememberedFact], cid: String?) async {
        guard !facts.isEmpty, companyId == cid else { return }
        let extracted = facts.map { ExtractedDecision(topic: $0.topic, statement: $0.statement, source: "chat") }
        let now = Date().timeIntervalSince1970 * 1000
        company.decisions = Decisions.mergeDecisions(existing: company.decisions, extracted: extracted, now: now)
        if let cid { _ = await decisionsSaver(cid, company.decisions) }
        guard companyId == cid else { return }
        // All facts land on the one reply rather than one bare row per fact — three
        // remembered facts used to mean three separate chips stacked under the bubble.
        if let i = inlineActionTarget(), chatMessages[i].noted == nil {
            chatMessages[i].noted = facts
        } else {
            for fact in facts {
                chatMessages.append(CopilotMessage(role: .companion, text: "", noted: [fact]))
            }
        }
    }

    /// Resolve + apply a tapped nav chip — mirrors `AppView.from(navDestination:)`.
    /// `department` additionally resolves `target` to a `DepartmentCatalog` key and
    /// opens that department's detail view (`selectedDeptKey`) instead of the roster;
    /// any other destination clears it so the tab opens on its default content.
    func activateNav(_ nav: NavAction) {
        guard let dest = AppView.from(navDestination: nav.destination) else { return }
        selectedDeptKey = nav.destination == "department" ? Self.resolveDepartmentKey(nav.target) : nil
        select(dest)
    }

    /// Resolve a `nav(department)` action's `target` to a `DepartmentCatalog` key —
    /// exact key match first (already-a-key targets), then a case-insensitive name
    /// match (the CF may send the human-readable department name instead).
    private static func resolveDepartmentKey(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let byKey = DepartmentCatalog.find(trimmed.lowercased()) { return byKey.key }
        let lowered = trimmed.lowercased()
        return DepartmentCatalog.all.first { $0.name.lowercased() == lowered }?.key
    }

    /// Resolve a tapped setup card's {category,name} to a `Toolkit` item and enable
    /// it — GUARDED: `toggleTool` is a true toggle, so only call it when the item is
    /// currently OFF (an already-on item, or a stale/duplicate tap, must never flip
    /// it back off).
    func activateSetup(_ setup: SetupAction) async {
        guard let item = Toolkit.find(category: setup.category, name: setup.name),
              !company.enabledTools.contains(item.id) else { return }
        await toggleTool(id: item.id)
    }

    /// Approve a chat draft: append it to the library (approved) + persist.
    func approveDraft(messageId: String) async {
        guard let i = chatMessages.firstIndex(where: { $0.id == messageId }),
              let draft = chatMessages[i].draft, !chatMessages[i].draftApproved else { return }
        company.library.append(draft)
        chatMessages[i].draftApproved = true
        if let cid = companyId { _ = await librarySaver(cid, company.library) }
        Task { await rememberFromApproval(draft) }
    }

    /// Redo a chat draft: re-run its source task and replace the draft (fail-soft).
    /// `reviseNote` nil → blind re-run (unchanged behavior). Non-nil (a revise chip
    /// tap) → threads the note plus the draft's CURRENT body into the request so the
    /// CF revises in place instead of regenerating from scratch.
    func redoDraft(messageId: String, language: AppLanguage, reviseNote: String? = nil) async {
        guard let i = chatMessages.firstIndex(where: { $0.id == messageId }),
              let draft = chatMessages[i].draft, !chatMessages[i].draftApproved,
              let task = company.tasks.first(where: { $0.id == draft.sourceTaskId }) else { return }
        let cid = companyId
        let result = await taskRunner(runRequest(for: task, language: language,
                                                  reviseNote: reviseNote,
                                                  current: reviseNote != nil ? draft.body : nil))
        // Re-check approved too: an Approve that raced this re-run must win (don't
        // overwrite the just-approved draft's body under an "Added to Library" label).
        guard companyId == cid,
              let j = chatMessages.firstIndex(where: { $0.id == messageId }),
              !chatMessages[j].draftApproved,
              let fresh = buildDeliverable(from: result, task: task) else { return }
        chatMessages[j].draft = fresh
    }

    /// Revise a task's pending draft in place (task analog of `redoDraft`, for the
    /// draft-preview sheet's revise chips). Threads the note + the draft's CURRENT
    /// body into the run so the CF revises rather than regenerates, then replaces
    /// `company.tasks[i].draft` and persists via `tasksSaver` (where the draft lives —
    /// same as `runTask`). Account/state-guarded on both await boundaries: a no-op if
    /// the task is gone, done, or no longer drafted (e.g. an approve raced this run).
    func reviseTaskDraft(taskId: String, reviseNote: String, language: AppLanguage) async {
        guard let task = company.tasks.first(where: { $0.id == taskId }),
              let draft = task.draft, !task.done, task.drafted else { return }
        let cid = companyId
        let result = await taskRunner(runRequest(for: task, language: language,
                                                 reviseNote: reviseNote, current: draft.body))
        guard companyId == cid,
              let j = company.tasks.firstIndex(where: { $0.id == taskId }),
              !company.tasks[j].done, company.tasks[j].drafted,
              let fresh = buildDeliverable(from: result, task: task) else { return }
        company.tasks[j].draft = fresh
        if let cid { _ = await tasksSaver(cid, company.tasks) }
    }

    /// Build a RunTaskRequest for a task (grounded on brief + roadmap). `reviseNote`/
    /// `current` default nil — a first run or blind redo sends neither (unchanged
    /// wire shape); only a revise chip tap sets both.
    private func runRequest(for task: RoadmapTask, language: AppLanguage,
                             reviseNote: String? = nil, current: String? = nil) -> RunTaskRequest {
        RunTaskRequest(
            companyId: companyId, language: language.rawValue, companionId: company.companionId,
            context: ChatContext.compose(brief: company.brief, tasks: company.tasks, decisions: company.decisions,
                                          memoryEnabled: company.founderPrefs.memoryEnabled),
            taskId: task.id, taskTitle: task.title, taskDetail: task.detail,
            reviseNote: reviseNote, current: current)
    }

    /// Build a Deliverable from a run result — the 6A gates in one place: unique id,
    /// canonical createdAt, non-empty title (fallback task.title) + body. Returns nil
    /// on a nil result or empty body — never a malformed deliverable.
    private func buildDeliverable(from result: RunTaskResponse?, task: RoadmapTask) -> Deliverable? {
        let body = result?.body.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let result, !body.isEmpty else { return nil }
        let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return Deliverable(
            id: UUID().uuidString, kind: DeliverableKind(raw: result.kind),
            title: title.isEmpty ? task.title : title, body: body,
            createdAt: ISOTime.utc(Date()), sourceTaskId: task.id, payload: result.payload)
    }

    /// Execute-log pacing (tunable; tests set to 0 to stay instant). `execStepNanos`
    /// is the delay between revealing each step; `execDoneBeatNanos` is the hold after
    /// the result lands so the completed log reads before collapsing to the draft.
    static var execStepNanos: UInt64 = 420_000_000
    static var execDoneBeatNanos: UInt64 = 260_000_000

    /// The execute-log steps for a run — a truthful description of the pipeline the
    /// deliverable goes through (the request genuinely carries the brief, decisions,
    /// and department context). Revealed progressively as the run proceeds.
    static func execSteps(task: RoadmapTask, specialist: (companionId: String, deptName: String)?,
                          decisionCount: Int, language: AppLanguage) -> [ExecStep] {
        let vi = language == .vi
        var out: [ExecStep] = []
        let ctx = decisionCount > 0
            ? (vi ? "Đọc brief — sứ mệnh, khách hàng, giọng điệu (và \(decisionCount) quyết định)"
                  : "Reading your brief — mission, audience, your voice (+ \(decisionCount) decisions)")
            : (vi ? "Đọc brief — sứ mệnh, khách hàng, giọng điệu của bạn"
                  : "Reading your brief — mission, audience, your voice")
        out.append(ExecStep(label: ctx))
        if let s = specialist {
            out.append(ExecStep(label: vi ? "Vận dụng cẩm nang \(s.deptName)" : "Pulling in the \(s.deptName) playbook"))
        }
        out.append(ExecStep(label: vi ? "Soạn \(task.title)" : "Drafting \(task.title)"))
        out.append(ExecStep(label: vi ? "Khớp giọng điệu và quyết định của bạn" : "Matching your tone and past decisions"))
        return out
    }

    /// Fan out the next actionable task in up to `maxFanOut` departments as parallel
    /// department-agent runs, shown live via `activeAgentRuns` (AgentsWorkingRow).
    /// Each agent's draft lands in the transcript as it finishes. Account-guarded.
    func fanOutNextMoves(language: AppLanguage) async {
        guard !isFanningOut, !isCompanionTyping, !isStreaming else { return }
        let plan = RoadmapEngine.nextMoves(company.tasks, limit: Self.maxFanOut)
        guard !plan.isEmpty else {
            // Empty fan-out is confined to the open window (gating), so it no longer means
            // "nothing left" — it can just as easily mean "nothing until you finish your own
            // step." Say which one it actually is: genuinely done vs. waiting on the founder.
            let text: String
            if let blocker = RoadmapGating.founderStep(in: company.tasks) {
                if blocker.drafted {
                    text = language == .vi
                        ? "Mình chưa chạy được gì tiếp — đang chờ bạn duyệt \"\(blocker.title)\" trước đã."
                        : "Nothing I can pick up yet — I'm waiting on you to approve \"\(blocker.title)\" first."
                } else {
                    text = language == .vi
                        ? "Mình chưa chạy được gì tiếp — đang chờ bạn xong \"\(blocker.title)\" trước đã."
                        : "Nothing I can pick up yet — I'm waiting on you to finish \"\(blocker.title)\" first."
                }
            } else {
                text = language == .vi
                    ? "Bạn đang không có việc nào mình chạy được ngay — lộ trình đã gọn rồi."
                    : "You're all caught up — no open tasks I can run right now."
            }
            chatMessages.append(CopilotMessage(role: .companion, text: text))
            flushActiveThread()
            return
        }
        let cid = companyId
        isFanningOut = true

        let now = Date()
        var seeded: [(run: AgentRun, task: RoadmapTask)] = []
        for task in plan {
            let deptName = DepartmentCatalog.find(task.dept)?.name ?? (task.dept ?? "")
            let companionId = task.dept.flatMap { DepartmentCompanions.companionId(for: $0) }
                ?? company.companionId
            let specialist: (companionId: String, deptName: String)? =
                deptName.isEmpty ? nil : (companionId, deptName)
            let steps = Self.execSteps(task: task, specialist: specialist,
                                       decisionCount: company.decisions.count, language: language)
            let run = AgentRun(id: task.id, companionId: companionId, deptName: deptName,
                               taskTitle: task.title, steps: steps, status: .working, startedAt: now)
            seeded.append((run, task))
        }
        activeAgentRuns = seeded.map { $0.run }

        await withTaskGroup(of: Void.self) { group in
            for item in seeded {
                group.addTask {
                    await self.runFanOutAgent(runId: item.run.id, task: item.task,
                                              cid: cid, language: language)
                }
            }
        }

        guard companyId == cid else { activeAgentRuns = []; isFanningOut = false; return }
        try? await Task.sleep(nanoseconds: Self.execDoneBeatNanos)   // let final pills show
        guard companyId == cid else { activeAgentRuns = []; isFanningOut = false; return }
        activeAgentRuns = []
        isFanningOut = false
        flushActiveThread()
    }

    /// One agent's run inside a fan-out: reveal its steps client-side while its
    /// `taskRunner` call runs, then flip its `AgentRun` to done/failed and append
    /// its draft (or an honest failure bubble). Mutations are main-actor; the
    /// `taskRunner` await is where parallelism happens. Account-guarded via `cid`.
    private func runFanOutAgent(runId: String, task: RoadmapTask,
                                cid: String?, language: AppLanguage) async {
        let reveal = Task { [cid] in
            let stepCount = activeAgentRuns.first(where: { $0.id == runId })?.steps.count ?? 0
            for idx in 0..<max(0, stepCount - 1) {
                try? await Task.sleep(nanoseconds: Self.execStepNanos)
                guard companyId == cid,
                      let ri = activeAgentRuns.firstIndex(where: { $0.id == runId }) else { return }
                activeAgentRuns[ri].steps[idx].done = true
            }
        }
        let result = await taskRunner(runRequest(for: task, language: language))
        _ = await reveal.value
        guard companyId == cid else { return }

        if let ri = activeAgentRuns.firstIndex(where: { $0.id == runId }) {
            for i in activeAgentRuns[ri].steps.indices { activeAgentRuns[ri].steps[i].done = true }
        }
        let companionId = activeAgentRuns.first(where: { $0.id == runId })?.companionId
        let deptName = activeAgentRuns.first(where: { $0.id == runId })?.deptName
        if let draft = buildDeliverable(from: result, task: task) {
            if let ri = activeAgentRuns.firstIndex(where: { $0.id == runId }) {
                activeAgentRuns[ri].status = .done
            }
            chatMessages.append(CopilotMessage(role: .companion, text: "", draft: draft,
                                               companionId: companionId, deptName: deptName))
        } else {
            if let ri = activeAgentRuns.firstIndex(where: { $0.id == runId }) {
                activeAgentRuns[ri].status = .failed
            }
            chatMessages.append(CopilotMessage(role: .companion, text: language == .vi
                ? "Không hoàn thành được \u{201C}\(task.title)\u{201D}. Thử lại nhé."
                : "Couldn't finish \u{201C}\(task.title)\u{201D} — try again.",
                companionId: companionId, deptName: deptName))
        }
    }

    /// Run a codepetCanDo task → produce a Deliverable → stash it as the task's `draft`
    /// and mark the task `drafted` (moves it to "Awaiting approval"). Does NOT write the
    /// library — the deliverable is copied there only on approve. Dedupe: a task already
    /// drafted & awaiting approval is not re-run (mirrors web's "you already have a
    /// draft"), so repeat taps never duplicate work. Fail-open + account-guarded.
    func runTask(_ task: RoadmapTask, language: AppLanguage) async {
        guard !runningTaskIds.contains(task.id) else { return }
        if let i = company.tasks.firstIndex(where: { $0.id == task.id }),
           company.tasks[i].done || company.tasks[i].drafted { return }   // done or already drafted → no regen/dup
        runningTaskIds.insert(task.id)
        runError = nil
        let cid = companyId
        let result = await taskRunner(runRequest(for: task, language: language))
        runningTaskIds.remove(task.id)
        guard companyId == cid else { return }
        guard let deliverable = buildDeliverable(from: result, task: task) else {
            runError = language == .vi
                ? "Không tạo được \"\(task.title)\" — thử lại nhé."
                : "Couldn't generate \"\(task.title)\" — try again."
            return
        }
        guard let i = company.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        // The `runningTaskIds` guard above ran BEFORE the `taskRunner` await, so
        // mark-complete ("I already did this") may have set `done = true` on this task
        // while the run was in flight — `runningTaskIds` only blocks a second RUN from
        // starting, not the panel's mark-done. Writing `drafted` onto a done task
        // strands the draft forever: `RoadmapEngine.status` short-circuits to `.done`
        // before ever consulting `drafted`, `approveTask` refuses (its own `!done`
        // guard), and the library never receives it — so skip the write when done wins.
        guard !company.tasks[i].done else { return }
        company.tasks[i].draft = deliverable
        company.tasks[i].drafted = true
        if let cid { _ = await tasksSaver(cid, company.tasks) }
    }

    /// Approve a task's draft: copy it into the library exactly once, mark the task done,
    /// and clear the draft/drafted state. Persists both tasks + library. Idempotent — a
    /// task with no pending draft, or already done, is a no-op (no duplicate library entry).
    func approveTask(id: String) async {
        guard let i = company.tasks.firstIndex(where: { $0.id == id }),
              let draft = company.tasks[i].draft, !company.tasks[i].done else { return }
        let approved = draft
        company.library.append(draft)
        company.tasks[i].done = true
        company.tasks[i].drafted = false
        company.tasks[i].draft = nil
        if let cid = companyId {
            _ = await librarySaver(cid, company.library)
            _ = await tasksSaver(cid, company.tasks)
        }
        Task { await rememberFromApproval(approved) }
    }

    /// Fire-and-forget after an approval: extract durable decisions the deliverable locks
    /// in, merge into memory, persist. Account-guarded + fail-open — a failed extract leaves
    /// decisions unchanged; the approval already happened. `dept` comes from the source task.
    ///
    /// `memoryEnabled` off withholds the facts on record here for the same reason
    /// `ChatContext.compose` drops them: `extractDecisions` renders every entry it is handed
    /// into a real model prompt ("- topic: statement"), so approving a deliverable with memory
    /// off would ship the whole store to the model — the exact thing the switch promises not to
    /// do. The extract path takes an empty list fine (it just has nothing to dedupe against),
    /// and RECORDING is untouched: what the deliverable itself locks in is still merged and
    /// persisted, so the panel keeps showing it. Off stops USE, not recording.
    private func rememberFromApproval(_ deliverable: Deliverable) async {
        let cid = companyId
        let dept = company.tasks.first { $0.id == deliverable.sourceTaskId }?.dept ?? ""
        let dto = ApprovedDeliverableDTO(title: deliverable.title, dept: dept,
                                         type: deliverable.kind.rawValue, out: deliverable.body)
        let onRecord = company.founderPrefs.memoryEnabled ? company.decisions : []
        let extracted = await decisionExtractor(dto, onRecord)
        guard companyId == cid, !extracted.isEmpty else { return }
        let now = Date().timeIntervalSince1970 * 1000
        company.decisions = Decisions.mergeDecisions(existing: company.decisions, extracted: extracted, now: now)
        if let cid { _ = await decisionsSaver(cid, company.decisions) }
    }

    /// Run the greeting's "Do it with me" task → append an inline draft (reuses the 6C
    /// run path). Marks the action consumed (optimistic, idempotent); in-flight +
    /// account-switch guarded; fail-open honest message on a nil result.
    func runFirstRunAction(messageId: String, language: AppLanguage) async {
        guard let i = chatMessages.firstIndex(where: { $0.id == messageId }),
              let action = chatMessages[i].firstRunAction,
              !chatMessages[i].actionConsumed,
              let task = company.tasks.first(where: { $0.id == action.taskId }),
              !runningTaskIds.contains(task.id) else { return }
        chatMessages[i].actionConsumed = true
        runningTaskIds.insert(task.id)
        let cid = companyId
        let result = await taskRunner(runRequest(for: task, language: language))
        runningTaskIds.remove(task.id)
        guard companyId == cid else { return }
        if let draft = buildDeliverable(from: result, task: task) {
            chatMessages.append(CopilotMessage(role: .companion, text: "", draft: draft))
        } else {
            // Restore the one-tap action so the "try again" copy stays honest (the task
            // was never drafted/done). Double-tap stays safe: runningTaskIds is already
            // clear and the in-flight guard held for the duration of the await.
            if let gi = chatMessages.firstIndex(where: { $0.id == messageId }) {
                chatMessages[gi].actionConsumed = false
            }
            chatMessages.append(CopilotMessage(role: .companion, text: language == .vi
                ? "Không tạo được ngay bây giờ — thử lại nhé."
                : "Couldn't generate that just now — try again."))
        }
    }

    /// Clear the transient run error (e.g. when the board's error line is dismissed).
    func clearRunError() { runError = nil }

    /// Set + persist the company's companion (fail-soft). Mirrors the toggleTool
    /// pattern: sync mutate, persist with the captured companyId, no post-await mutation.
    func setCompanion(id: String) async {
        company.companionId = id
        if let cid = companyId { _ = await companionSaver(cid, id) }
    }

    /// Persist the founder's preferred name onto the brief. Reuses the ONE brief writer
    /// (`saver`, the injected `CompanyData.saveBrief` that `answerInterview` and
    /// `finishOnboarding` already go through) rather than adding a second write path for a
    /// field the brief document already owns. Fail-soft: a lost write only means the old
    /// name comes back on reload, never a broken page.
    ///
    /// Guarded against a `hydrate`/`reset` landing mid-flight: `PreferencesPanel` commits
    /// the draft on `.onDisappear`, which can fire from inside a sign-out/account switch —
    /// and `hydrate` flips `companyId` to the INCOMING account before `company` is actually
    /// loaded for it (see its doc comment). A write issued in that window would attach the
    /// OUTGOING founder's draft, on the not-yet-loaded brief, to the INCOMING account's
    /// document. `isHydrating` is true for exactly that window, so bail before touching
    /// `company`/`saver` at all while it holds. The same token captured up front is
    /// re-checked after the save's own await (mirroring `finishOnboarding`), so a
    /// hydrate/reset that lands DURING the write also drops the stale in-memory commit
    /// instead of clobbering the newly-hydrated company. Either path drops the write
    /// rather than mis-attributing it.
    func setFounderName(_ name: String) async {
        let token = hydrationToken
        guard !isHydrating, let cid = companyId else { return }
        var brief = company.brief
        brief.founderName = name
        _ = await saver(cid, brief)
        guard token == hydrationToken, companyId == cid else { return }
        company.brief = brief
    }

    /// Persist the founder's settings-modal preferences onto the company doc, so they follow
    /// the account across machines instead of living in UserDefaults. Fail-soft, like
    /// `setCompanion`: a lost write only means the previous preferences come back on reload.
    ///
    /// Carries `setFounderName`'s guard, for the same reason: a settings panel can commit a
    /// draft from inside a sign-out / account switch, and `hydrate` flips `companyId` to the
    /// INCOMING account BEFORE `company` is loaded for it. A write issued in that window
    /// would attach the OUTGOING founder's preferences to the INCOMING account's document.
    /// `isHydrating` covers exactly that window, and the token captured up front is
    /// re-checked after the save's await so a hydrate/reset landing DURING the write drops
    /// the stale in-memory commit instead of clobbering the newly-hydrated company.
    ///
    /// ALSO sequenced per write, a different hazard on the same account: every settings
    /// panel commits from an untracked `Task` (a picker changed twice quickly fires two),
    /// so two saves can be in flight at once and finish in either order. Without this the
    /// OLDER write's `company.founderPrefs = next` would land last and clobber the newer
    /// choice — and the panels seed their drafts off `company`, so the stale value would then
    /// be re-persisted. `founderPrefsWriteToken` is bumped per call and re-checked after the
    /// await (same idiom as `hydrationToken`), so a superseded write still persists but never
    /// applies its result. Both guards are needed: the hydration token cannot see a second
    /// write on the SAME account, and this one cannot see an account switch.
    ///
    /// AND field-scoped, which is what makes three panels sharing one blob safe. `change` is
    /// applied to `pendingFounderPrefs ?? company.founderPrefs` — the latest INTENDED value —
    /// not to a copy the caller captured earlier, so a commit contributes ONLY its own field.
    /// Every panel used to capture the whole struct and write it back, so a commit issued
    /// while another panel's write was in flight resurrected that panel's stale value: turn
    /// memory off, switch to Notifications, change a picker before the first write returned,
    /// and `memoryEnabled` silently reverted to `true`. `founderPrefsWriteToken` cannot help
    /// there — both writes are legitimate and touch different fields of one struct — which is
    /// why the composition, not the sequencing, is the fix. The token stays load-bearing for
    /// the case it was written for (two commits of the SAME field), and composing makes it
    /// strictly safe: the newest write's value now carries every older write's change too, so
    /// dropping a superseded commit loses nothing.
    func updateFounderPrefs(_ change: (inout FounderPrefs) -> Void) async {
        let token = hydrationToken
        guard !isHydrating, let cid = companyId else { return }
        let base = pendingFounderPrefs ?? company.founderPrefs
        var next = base
        change(&next)
        guard next != base else { return }   // nothing actually changed → no write
        pendingFounderPrefs = next
        // Bumped only once past the guards, so a call dropped for hydration never
        // supersedes a legitimate write already in flight.
        founderPrefsWriteToken &+= 1
        let writeToken = founderPrefsWriteToken
        _ = await founderPrefsSaver(cid, next)
        guard token == hydrationToken, companyId == cid else { return }
        guard writeToken == founderPrefsWriteToken else { return }  // a newer write superseded us
        company.founderPrefs = next
        codingMemoryGate(next.memoryEnabled)
        // Only the newest write reaches here, and it just made the visible value match the
        // intent, so nothing is in flight any more.
        pendingFounderPrefs = nil
    }

    /// Forget one fact the founder's team was told — the delete half of the Memory panel,
    /// and the reason that panel can be trusted at all: today a fact recorded by
    /// `remember_fact` can never be taken back.
    ///
    /// Persists through the EXISTING `decisionsSaver`, the same path `handleRemember` and
    /// `lockInVirtualCompanyDecision` write on, so decisions still reach the document
    /// exactly one way. Matched on `Decisions.identityKey` — the trimmed, lowercased topic the
    /// merge itself keys on — rather than by index or on topic + statement: a `remember_fact`
    /// merge landing between render and tap can both re-order the array AND rewrite the
    /// statement of the very row being deleted, and matching the statement would then make
    /// that fact permanently undeletable (the ✕ a silent no-op). `firstIndex` is kept so a doc
    /// that somehow holds duplicate topics loses ONE row per tap, not both. A topic that is
    /// not on record is a silent no-op, not a redundant write.
    ///
    /// The surviving list is re-derived from `company.decisions` AFTER the write, never
    /// assigned from a snapshot taken before it: a merge on this same account (same hydration
    /// token, so the guard below cannot see it) can land inside that await, and assigning a
    /// pre-computed array would erase the freshly-remembered fact from memory. When the
    /// re-derived list differs from what was persisted, one corrective write — through the same
    /// `decisionsSaver`, no new path — converges the document on it.
    ///
    /// Carries `updateFounderPrefs`'s hydration guard, for exactly the same reason: the
    /// settings modal can stay open across a sign-out / account switch, and `hydrate` flips
    /// `companyId` to the INCOMING account BEFORE `company` is loaded for it. A delete
    /// issued in that window would run against the OUTGOING founder's list and be written
    /// to the INCOMING founder's document. `isHydrating` is true for exactly that window,
    /// and the token captured up front is re-checked after the write's await so a
    /// hydrate/reset landing DURING it drops the stale in-memory removal instead of
    /// clobbering the newly-hydrated company.
    func forgetDecision(_ entry: DecisionEntry) async {
        let token = hydrationToken
        guard !isHydrating, let cid = companyId else { return }
        let target = Decisions.identityKey(entry.topic)
        guard let attempted = Self.dropping(target, from: company.decisions) else { return }
        _ = await decisionsSaver(cid, attempted)
        guard token == hydrationToken, companyId == cid else { return }
        // Re-derive off the CURRENT list, so a merge that landed during the write survives.
        let remaining = Self.dropping(target, from: company.decisions) ?? company.decisions
        company.decisions = remaining
        if remaining != attempted { _ = await decisionsSaver(cid, remaining) }
    }

    /// `decisions` minus the first entry whose identity is `target`, or nil when that topic is
    /// not on record (the caller's no-op case, kept distinct from "removed nothing").
    private static func dropping(_ target: String, from decisions: [DecisionEntry]) -> [DecisionEntry]? {
        guard let i = decisions.firstIndex(where: { Decisions.identityKey($0.topic) == target })
        else { return nil }
        var remaining = decisions
        remaining.remove(at: i)
        return remaining
    }

    /// Remember that this account has seen the Overview briefing, so the first-run modal shows
    /// once per account rather than once per device. Fail-soft: a lost write only means the
    /// briefing appears one more time, never a broken page.
    func markIntroSeen() async {
        guard company.introSeenAt == nil else { return }
        let now = Date()
        company.introSeenAt = now
        if let cid = companyId { _ = await introSeenSaver(cid, now) }
    }

    /// Enable/disable a toolkit item and persist (fail-soft).
    /// Connector ids the founder has actually authorised, read from the server.
    ///
    /// Kept separate from `company.enabledTools` on purpose: that set is a local
    /// preference the client owns, while this one is a fact about a stored OAuth
    /// token that only the backend can establish. A connector row shows *this*,
    /// so it can never claim "Connected" for a token that does not exist.
    @Published private(set) var connectedProviders: Set<String> = []

    func refreshConnectorStatus() async {
        guard let cid = companyId else { return }
        connectedProviders = await CompanyData.loadConnectorStatus(cid)
    }

    /// Run a provider's consent flow, then reconcile from the server rather than
    /// assuming success — the token is written by the Cloud Function, so the
    /// server is the only thing that knows whether it landed.
    @discardableResult
    func connectProvider(_ provider: ConnectorProvider) async -> ConnectorAuthResult {
        let result = await ConnectorAuth.shared.connect(provider)
        guard result == .connected else { return result }
        await refreshConnectorStatus()
        // Mirror into the toolkit flag so everything that already reads
        // `enabledTools` — byte's env_setup list, the usage receipts — sees the
        // connector as available, without those call sites learning about OAuth.
        if connectedProviders.contains(provider.toolId),
           !company.enabledTools.contains(provider.toolId) {
            await toggleTool(id: provider.toolId)
        }
        return result
    }

    func toggleTool(id: String) async {
        if company.enabledTools.contains(id) {
            company.enabledTools.remove(id)
        } else {
            company.enabledTools.insert(id)
        }
        if let cid = companyId { _ = await toolsSaver(cid, Array(company.enabledTools)) }
    }

    /// Clear on sign-out / account switch.
    func reset() {
        hydrationToken &+= 1
        companyId = nil
        company = .empty
        // Read off the company we just reset to (so it can't drift from what `reset()`
        // assigns), which means the default: memory ON. The NEXT account therefore never
        // inherits the outgoing founder's switch — `hydrate` pushes theirs.
        codingMemoryGate(company.founderPrefs.memoryEnabled)
        // Same reason as in `hydrate`: the outgoing founder's in-flight settings change must
        // not be composed onto the next account's preferences.
        pendingFounderPrefs = nil
        view = .roadmap
        isHydrating = false
        isOnboarding = false
        chatMessages = []
        chatDraft = ""
        threads = []
        activeThreadId = nil
        isCompanionTyping = false
        isStreaming = false
        runningTaskIds = []
        activeAgentRuns = []
        isFanningOut = false
        runError = nil
        isGeneratingRoadmap = false   // clear here too: reset() bumps hydrationToken, so an
        // in-flight generateRoadmap's token-guarded defer won't clear it (would stick the
        // "Re-plan" button disabled forever otherwise).
        interviewState = nil
        // Session state about the OUTGOING founder. Leaving it true would mean the
        // next account — empty brief, nothing on record — is never asked at all,
        // because `hydrate` only ever sets it from the incoming company's flag and a
        // sign-out with no re-hydrate would keep this stale `true`.
        vcInterviewAsked = false
        // The outgoing founder's runs. The account guard already stops a late frame
        // from landing in the incoming account's chat; cancelling also ends the
        // server's work — and its spend — rather than paying for a verdict nobody
        // will ever be shown. Cancellation propagates through the stream's
        // `onTermination` into the client's detached task.
        for task in vcTasks.values { task.cancel() }
        vcTasks = [:]
        selectedDeptKey = nil
        // The settings overlay only renders inside `AppShellView`, so signing out with it
        // open hides it without closing it — leaving this set would hand the NEXT account
        // a settings panel over their first frame of the shell.
        settingsSection = nil
        activeProjectLink = nil
        codingRunAnchorId = nil
        codingRun.cancel()   // clear any run anchored in the just-reset conversation (no-op while running)
    }
}
