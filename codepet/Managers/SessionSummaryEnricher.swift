import Foundation
import Combine
import os

/// Triggers session-level summarization. Decides which sessions need
/// summarizing based on:
///   - explicit SessionEnd signal (immediate), OR
///   - idle ≥ idleThreshold (default 30 min) since last activity
@MainActor
final class SessionSummaryEnricher: ObservableObject {

    let objectWillChange = PassthroughSubject<Void, Never>()

    private let api: ReflectionAPIClientProtocol
    private let store: SessionSummaryStore
    var projectStore: ProjectStore?
    /// The Learner Model's data-collection layer. When a session summary carries
    /// `growth_signals`, they're banked here for the UI today and the model later.
    var agencyLog: AgencySignalLog?
    var language: String
    private let idleThreshold: TimeInterval
    /// Hard ceiling on a single session-summary stream so a hung SSE connection
    /// can't pin the session in an un-summarized state forever.
    private let streamTimeout: TimeInterval
    private var inFlight: Set<String> = []
    private let logger = Logger(subsystem: "app.murror.codepet", category: "SessionSummaryEnricher")

    init(
        api: ReflectionAPIClientProtocol,
        store: SessionSummaryStore,
        projectStore: ProjectStore? = nil,
        language: String,
        idleThreshold: TimeInterval = 30 * 60,
        streamTimeout: TimeInterval = 60
    ) {
        self.api = api
        self.store = store
        self.projectStore = projectStore
        self.language = language
        self.idleThreshold = idleThreshold
        self.streamTimeout = streamTimeout
    }

    private struct StreamTimeout: Error {}

    /// Returns true if a session should be auto-summarized:
    ///   - it has at least 1 turn with a closed (ended) state
    ///   - it has no summary yet
    ///   - either it's in endedSessionIds, OR last activity was > idleThreshold ago
    func shouldAutoSummarize(
        session: Session,
        endedSessionIds: Set<String>,
        now: Date = Date()
    ) -> Bool {
        guard session.summary == nil else { return false }
        guard session.turns.contains(where: { $0.endedAt != nil }) else { return false }
        // Don't auto-summarize sessions with no tool events (no file edits,
        // no bash commands). These are "check-in" sessions with only text replies.
        guard session.hasMeaningfulWork else { return false }
        // A split-off segment's id is "<cliId>#2"; the CLI session-end event
        // records only the raw cliId, so also match on the prefix before "#".
        // Without this, later segments would miss the instant end-trigger and
        // wait for the 30-min idle path instead. (The first/morning segment
        // keeps the raw id and already has its summary, so it won't re-fire.)
        let rawSessionId = session.id.components(separatedBy: "#").first ?? session.id
        if endedSessionIds.contains(session.id) || endedSessionIds.contains(rawSessionId) { return true }
        let lastActivity = session.turns.compactMap { $0.endedAt ?? $0.startedAt }.max() ?? session.startedAt
        return now.timeIntervalSince(lastActivity) > idleThreshold
    }

    /// Trigger summarization for a session. Idempotent — won't re-fire if in-flight.
    /// Uses SSE streaming so the Cloud Function responds faster (first byte ~1s).
    /// When `isAutoTriggered` is true (session-end / idle timeout), the brief_update
    /// from the LLM is appended to the project brief as a dated changelog entry.
    @discardableResult
    func enrich(
        session: Session,
        petPersona: SummarizeTurnRequest.PetPersonaDTO? = nil,
        isAutoTriggered: Bool = false
    ) async -> Bool {
        guard !inFlight.contains(session.id) else { return false }
        inFlight.insert(session.id)
        defer { inFlight.remove(session.id) }

        let request = makeRequest(for: session, persona: petPersona)
        do {
            // Race the stream against a timeout so a hung connection fails fast
            // instead of leaving the session permanently un-summarized.
            let timeout = streamTimeout
            let collected: (SummarizeSessionResponse.SummaryPayload, String, String?, String?)?
            collected = try await withThrowingTaskGroup(
                of: (SummarizeSessionResponse.SummaryPayload, String, String?, String?)?.self
            ) { group in
                group.addTask { [self] in
                    var summaryPayload: SummarizeSessionResponse.SummaryPayload?
                    var model = ""
                    var briefUpdate: String?
                    var projectOverview: String?
                    for try await event in api.summarizeSessionStream(request) {
                        switch event {
                        case .started, .jsonDelta:
                            break
                        case .done(let payload, let m, let bu, let po):
                            summaryPayload = payload
                            model = m
                            briefUpdate = bu
                            projectOverview = po
                        }
                    }
                    guard let payload = summaryPayload else { return nil }
                    return (payload, model, briefUpdate, projectOverview)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw StreamTimeout()
                }
                defer { group.cancelAll() }
                return try await group.next() ?? nil
            }

            guard let (payload, model, briefUpdate, projectOverview) = collected else {
                logger.warning("session stream completed without summary for \(session.id)")
                return false
            }

            let summary = SessionSummary(
                sessionId: session.id,
                summary: payload.summary,
                lesson: payload.lesson,
                generatedAt: Date(),
                model: model,
                schemaVersion: 1
            )
            do {
                try store.appendSummary(summary)
            } catch {
                logger.error("failed to persist session summary: \(error.localizedDescription)")
            }

            // Bank the process-literacy "growth edge" signals for this session.
            // Absent until the server function is redeployed with the contract.
            if let dtos = payload.growthSignals, !dtos.isEmpty, let log = agencyLog {
                let now = Date()
                let banked = dtos.map { dto in
                    AgencySignal(
                        id: "\(session.id)__\(dto.signal)__\(dto.valence)",
                        sessionId: session.id,
                        observation: dto.observation,
                        axis: dto.axis,
                        signal: dto.signal,
                        valence: dto.valence,
                        evidence: dto.evidence,
                        language: language,
                        createdAt: now
                    )
                }
                log.record(banked)
                logger.info("banked \(banked.count) agency signal(s) for \(session.id)")
            }

            // Auto-update project brief: overview (description) + changelog entry.
            // Resolve the raw cwd to the canonical project root (ProjectStore keys
            // by resolved root, not raw cwd).
            logger.info("Brief update pipeline: briefUpdate=\(briefUpdate ?? "<nil>"), overview=\(projectOverview ?? "<nil>"), rawPath=\(session.projectPath ?? "<nil>")")
            if let ps = projectStore {
                let resolvedPath = ps.resolvedProjectPath(for: session.projectPath, sessionId: session.id)
                logger.info("Brief update resolved path: \(resolvedPath ?? "<nil>"), projectExists=\(ps.project(for: resolvedPath) != nil)")
                if let projectPath = resolvedPath {
                    updateProjectBrief(
                        overview: projectOverview,
                        changelog: briefUpdate,
                        projectPath: projectPath,
                        projectStore: ps
                    )
                }
            } else {
                logger.warning("Brief update skipped: projectStore is nil")
            }

            // Record in pet memory for cross-session personalization
            let resolvedForMemory = projectStore?.resolvedProjectPath(for: session.projectPath, sessionId: session.id) ?? session.projectPath
            let durationMin: Int = {
                guard let ended = session.endedAt else { return 0 }
                return max(1, Int(ended.timeIntervalSince(session.startedAt) / 60))
            }()
            PetMemoryStore.shared.recordSessionEnd(
                projectPath: resolvedForMemory,
                sessionDate: session.endedAt ?? Date(),
                durationMinutes: durationMin,
                summary: payload.summary,
                lesson: payload.lesson,
                filesWorkedOn: session.filePaths
            )

            return true
        } catch {
            logger.warning("session enrichment failed for \(session.id): \(String(describing: error))")
            return false
        }
    }

    /// Updates the project brief: appends a dated changelog entry. The user's
    /// description is preserved as-is (never overwritten by the LLM `overview`).
    private func updateProjectBrief(
        overview: String?,
        changelog: String?,
        projectPath: String,
        projectStore ps: ProjectStore
    ) {
        let currentBrief = ps.brief(for: projectPath)
        let separator = "\n\n---\n"

        // Split current brief into description + existing changelog
        let parts: (desc: String, log: String)
        if let sepRange = currentBrief.range(of: separator) {
            parts = (
                String(currentBrief[currentBrief.startIndex..<sepRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines),
                String(currentBrief[sepRange.lowerBound...])
            )
        } else {
            parts = (currentBrief.trimmingCharacters(in: .whitespacesAndNewlines), "")
        }

        // Auto-fill the description from the LLM project_overview, but ONLY when
        // it is currently empty. Once there is any description (user-written, or
        // a previous auto-fill), it is left untouched. This restores the "auto
        // brief overview" — a blank brief box gets populated automatically — while
        // structurally preventing the de279c0 regression, where the overview
        // clobbered every project's existing description with a generic blurb.
        // The server's overview is now grounded in the session + current brief,
        // so for a project with real history it describes THIS project, not a
        // generic app.
        let overviewTrimmed = (overview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let didAutoFillDesc = parts.desc.isEmpty && !overviewTrimmed.isEmpty
        let newDesc = parts.desc.isEmpty ? overviewTrimmed : parts.desc

        // Append new changelog entry (if provided and non-empty)
        let changelogTrimmed = (changelog ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var newLog = parts.log
        if !changelogTrimmed.isEmpty {
            let dateStr = Self.briefDateFormatter.string(from: Date())
            newLog += "\n\n---\n**\(dateStr)**: \(changelogTrimmed)"
        }

        let updatedBrief = newDesc + newLog
        guard updatedBrief != currentBrief else {
            logger.info("Brief unchanged, skipping update")
            return
        }
        ps.updateBrief(projectId: projectPath, brief: updatedBrief)
        // No ownership marking here: the per-session fill only writes an empty
        // description, and an empty/machine-written description stays writable
        // by the from-history synthesis. Only a hand-edit (ProjectBriefCard)
        // marks a brief user-owned.
        logger.info("Updated project brief for \(projectPath): desc=\(didAutoFillDesc ? "auto-filled" : "unchanged"), log=\(changelogTrimmed.isEmpty ? "unchanged" : "+entry")")
    }

    private static let briefDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private func makeRequest(
        for session: Session,
        persona: SummarizeTurnRequest.PetPersonaDTO?
    ) -> SummarizeSessionRequest {
        let turns = session.turns.map { turn -> SummarizeSessionRequest.TurnDTO in
            let durMin: Int? = {
                guard let ended = turn.endedAt else { return nil }
                return max(1, Int(ended.timeIntervalSince(turn.startedAt) / 60))
            }()
            return SummarizeSessionRequest.TurnDTO(
                prompt: turn.prompt,
                whatYouWanted: turn.narrative?.whatYouWanted,
                whatHappened: turn.narrative?.whatHappened,
                durationMinutes: durMin
            )
        }
        return SummarizeSessionRequest(
            sessionId: session.id,
            language: language,
            turns: turns,
            petPersona: persona,
            userBrief: NarrativeEnricher.currentUserBrief(projectPath: session.projectPath),
            petMemory: PetMemoryStore.shared.promptPayload(for: session.projectPath)
        )
    }
}
