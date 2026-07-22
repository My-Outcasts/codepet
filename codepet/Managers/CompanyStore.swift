// codepet/Managers/CompanyStore.swift
import Foundation
import Combine

/// The app's primary store — the single company (companies/{uid}) + the active
/// view. Native port of the web `useApp`/`lib/store`. Replaces ProjectStore's
/// role as the top-level store (ProjectStore/reflection are being retired).
@MainActor
final class CompanyStore: ObservableObject {
    @Published var view: AppView = .overview
    @Published private(set) var company: CompanyState = .empty
    @Published private(set) var isHydrating: Bool = false
    @Published private(set) var isOnboarding: Bool = false
    @Published private(set) var chatMessages: [CopilotMessage] = []
    @Published private(set) var isCompanionTyping = false
    @Published private(set) var runningTaskIds: Set<String> = []
    @Published private(set) var runError: String?
    @Published private(set) var isGeneratingRoadmap = false

    /// The hydrated company's id, needed for writes. Set by `hydrate`, cleared by `reset`.
    private(set) var companyId: String?

    /// Injectable so tests can supply a stub without Firestore.
    private let loader: (String) async -> CompanyState
    private let saver: (String, CompanyBrief) async -> Bool
    private let roadmapFetcher: (CompanyBrief, AppLanguage) async -> [RoadmapTask]
    private let tasksSaver: (String, [RoadmapTask]) async -> Bool
    private let chatSender: (CompanyChatRequest) async -> CompanyChatReply?
    private let taskRunner: (RunTaskRequest) async -> RunTaskResponse?
    private let librarySaver: (String, [Deliverable]) async -> Bool
    private let toolsSaver: (String, [String]) async -> Bool
    private let companionSaver: (String, String) async -> Bool

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

    init(loader: @escaping (String) async -> CompanyState = CompanyData.load,
         saver: @escaping (String, CompanyBrief) async -> Bool = CompanyData.saveBrief,
         roadmapFetcher: @escaping (CompanyBrief, AppLanguage) async -> [RoadmapTask] = CompanyData.fetchRoadmap,
         tasksSaver: @escaping (String, [RoadmapTask]) async -> Bool = CompanyData.saveTasks,
         chatSender: @escaping (CompanyChatRequest) async -> CompanyChatReply? = CompanyChatClient.send,
         taskRunner: @escaping (RunTaskRequest) async -> RunTaskResponse? = RunTaskClient.run,
         librarySaver: @escaping (String, [Deliverable]) async -> Bool = CompanyData.saveLibrary,
         toolsSaver: @escaping (String, [String]) async -> Bool = CompanyData.saveEnabledTools,
         companionSaver: @escaping (String, String) async -> Bool = CompanyData.saveCompanionId) {
        self.loader = loader
        self.saver = saver
        self.roadmapFetcher = roadmapFetcher
        self.tasksSaver = tasksSaver
        self.chatSender = chatSender
        self.taskRunner = taskRunner
        self.librarySaver = librarySaver
        self.toolsSaver = toolsSaver
        self.companionSaver = companionSaver
    }

    func select(_ view: AppView) { self.view = view }

    /// Mirrors the web: onboard unless a stamp exists OR the brief already has signal.
    var needsOnboarding: Bool {
        company.onboardedAt == nil && BriefContext.compose(company.brief) == nil
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
            isCompanionTyping = false
            runningTaskIds = []
            runError = nil
        }
        self.companyId = companyId
        isHydrating = true
        let loaded = await loader(companyId)
        guard token == hydrationToken else { return }  // a newer hydrate/reset superseded us
        company = loaded
        isHydrating = false
        isOnboarding = needsOnboarding
        onboardingToken = hydrationToken
    }

    /// Enrich already happened in the model; here we persist + stamp + leave onboarding.
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
        seedFirstRunGreeting(language: language)
    }

    /// Seed byte's first-run greeting (name + best first move + optional inline action)
    /// as one companion message. Called once, at the onboarding→app edge.
    private func seedFirstRunGreeting(language: AppLanguage) {
        guard companyId != nil else { return }
        let next = RoadmapEngine.nextStep(company.tasks)
        let g = FirstRunGreetingBuilder.build(brief: company.brief, nextStep: next, language: language)
        chatMessages.append(CopilotMessage(role: .companion, text: g.text, firstRunAction: g.action))
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
        _ = await saver(cid, brief)
        // Cancellation guard: a Skip during the in-flight scaffold cancels this task,
        // so we bail before mutating brief/tasks (skip's empty write is the winner).
        guard token == hydrationToken, !Task.isCancelled else { return .empty }
        company.brief = brief
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

    /// Send a founder message to the company companion (single reply, fail-open,
    /// session-only). Token-guarded: an account switch mid-reply discards the reply.
    func sendChat(_ raw: String, language: AppLanguage) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isCompanionTyping else { return }
        chatMessages.append(CopilotMessage(role: .me, text: text))
        isCompanionTyping = true
        let history = chatMessages.dropLast().suffix(20).map {
            ChatTurnDTO(role: $0.role == .me ? "me" : "companion", text: $0.text)
        }
        let cid = companyId
        let req = CompanyChatRequest(
            companyId: companyId, language: language.rawValue, companionId: company.companionId,
            context: ChatContext.compose(brief: company.brief, tasks: company.tasks),
            history: Array(history), userMessage: text)
        let reply = await chatSender(req)
        // Apply only if we're still on the same account. A real account switch
        // (companyId changed) already cleared chat + typing in hydrate/reset, so
        // the stale reply is dropped and typing is never left stuck.
        guard companyId == cid else { return }
        let offline = language == .vi
            ? "Mình không kết nối được lúc này — thử lại sau nhé."
            : "I can't reach my brain right now — try again in a bit."
        chatMessages.append(CopilotMessage(role: .companion, text: reply?.text ?? offline))
        // If byte chose to run a runnable task, produce a draft deliverable inline.
        if let runId = reply?.runTaskId,
           let task = company.tasks.first(where: { $0.id == runId }),
           RoadmapEngine.status(for: task, in: company.tasks) == .codepetCanDo {
            let result = await taskRunner(runRequest(for: task, language: language))
            guard companyId == cid else { return }
            if let draft = buildDeliverable(from: result, task: task) {
                chatMessages.append(CopilotMessage(role: .companion, text: "", draft: draft))
            } else {
                chatMessages.append(CopilotMessage(role: .companion, text: language == .vi
                    ? "Không tạo được ngay bây giờ — thử lại nhé."
                    : "Couldn't generate that just now — try again."))
            }
        }
        isCompanionTyping = false
    }

    /// Approve a chat draft: append it to the library (approved) + persist.
    func approveDraft(messageId: String) async {
        guard let i = chatMessages.firstIndex(where: { $0.id == messageId }),
              let draft = chatMessages[i].draft, !chatMessages[i].draftApproved else { return }
        company.library.append(draft)
        chatMessages[i].draftApproved = true
        if let cid = companyId { _ = await librarySaver(cid, company.library) }
    }

    /// Redo a chat draft: re-run its source task and replace the draft (fail-soft).
    func redoDraft(messageId: String, language: AppLanguage) async {
        guard let i = chatMessages.firstIndex(where: { $0.id == messageId }),
              let draft = chatMessages[i].draft, !chatMessages[i].draftApproved,
              let task = company.tasks.first(where: { $0.id == draft.sourceTaskId }) else { return }
        let cid = companyId
        let result = await taskRunner(runRequest(for: task, language: language))
        // Re-check approved too: an Approve that raced this re-run must win (don't
        // overwrite the just-approved draft's body under an "Added to Library" label).
        guard companyId == cid,
              let j = chatMessages.firstIndex(where: { $0.id == messageId }),
              !chatMessages[j].draftApproved,
              let fresh = buildDeliverable(from: result, task: task) else { return }
        chatMessages[j].draft = fresh
    }

    /// Build a RunTaskRequest for a task (grounded on brief + roadmap).
    private func runRequest(for task: RoadmapTask, language: AppLanguage) -> RunTaskRequest {
        RunTaskRequest(
            companyId: companyId, language: language.rawValue, companionId: company.companionId,
            context: ChatContext.compose(brief: company.brief, tasks: company.tasks),
            taskId: task.id, taskTitle: task.title, taskDetail: task.detail)
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
            createdAt: ISOTime.utc(Date()), sourceTaskId: task.id)
    }

    /// Run a codepetCanDo task → produce a Deliverable → append to the library + persist.
    /// Fail-open: a nil/empty result surfaces an honest runError and appends nothing.
    /// Task is left as-is. companyId-guarded against account switch mid-run.
    func runTask(_ task: RoadmapTask, language: AppLanguage) async {
        guard !runningTaskIds.contains(task.id) else { return }
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
        company.library.append(deliverable)
        if let cid { _ = await librarySaver(cid, company.library) }
    }

    /// Clear the transient run error (e.g. when the board's error line is dismissed).
    func clearRunError() { runError = nil }

    /// Set + persist the company's companion (fail-soft). Mirrors the toggleTool
    /// pattern: sync mutate, persist with the captured companyId, no post-await mutation.
    func setCompanion(id: String) async {
        company.companionId = id
        if let cid = companyId { _ = await companionSaver(cid, id) }
    }

    /// Enable/disable a toolkit item and persist (fail-soft).
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
        view = .overview
        isHydrating = false
        isOnboarding = false
        chatMessages = []
        isCompanionTyping = false
        runningTaskIds = []
        runError = nil
        isGeneratingRoadmap = false   // clear here too: reset() bumps hydrationToken, so an
        // in-flight generateRoadmap's token-guarded defer won't clear it (would stick the
        // "Re-plan" button disabled forever otherwise).
    }
}
