import Foundation
import Combine
import os

/// One-time, from-history project brief backfill.
///
/// The per-session enricher fills an empty brief from a single session's
/// `project_overview` — thin, because it only sees one session. This synthesizer
/// instead reads a project's ENTIRE session history (every past summary) and
/// asks the server to write one complete description of what the project IS.
///
/// Policy (chosen by the user): run ONCE per project (the result is then theirs
/// to revise; forward sessions only append to the changelog). It overwrites an
/// empty / auto-filled / legacy description, but NEVER one the user hand-edited
/// (tracked positively in ProjectStore via `markBriefUserOwned`).
@MainActor
final class BriefSynthesizer: ObservableObject {

    private let api: ReflectionAPIClientProtocol
    private let logger = Logger(subsystem: "app.murror.codepet", category: "BriefSynthesizer")

    /// Project paths currently being synthesized, so a re-entrant call (the
    /// session list recomputes often) doesn't fire duplicate requests.
    private var inFlight: Set<String> = []

    /// A project needs at least this many summarized sessions before a
    /// from-history synthesis is worth doing; below it, the per-session
    /// auto-fill is enough and we wait for more history to accumulate.
    private let minSessions: Int

    init(api: ReflectionAPIClientProtocol, minSessions: Int = 2) {
        self.api = api
        self.minSessions = minSessions
    }

    /// Group the assembled sessions by resolved project and kick off a backfill
    /// for each eligible project. Idempotent: projects already backfilled,
    /// user-owned, in-flight, or lacking history are skipped.
    func backfill(sessions: [Session], projectStore: ProjectStore, language: String) {
        var byProject: [String: [(date: Date, summary: SessionSummary)]] = [:]
        for s in sessions {
            guard let summary = s.summary else { continue }
            guard let path = projectStore.resolvedProjectPath(for: s.projectPath, sessionId: s.id),
                  projectStore.project(for: path) != nil else { continue }
            byProject[path, default: []].append((s.endedAt ?? s.startedAt, summary))
        }

        for (path, entries) in byProject {
            // Interview brief is the source of truth — never synthesize over it.
            // Defensive: covers a companyBrief that arrived (e.g. cloud sync)
            // without the markBriefUserOwned marker also being set.
            if projectStore.companyBrief(for: path) != nil {
                projectStore.markBriefBackfilled(projectPath: path)
                continue
            }
            guard !projectStore.briefBackfillDone(projectPath: path) else { continue }
            // User-owned description: never touch it; mark done so we stop checking.
            guard projectStore.briefDescriptionIsSynthesisWritable(projectPath: path) else {
                projectStore.markBriefBackfilled(projectPath: path)
                continue
            }
            guard entries.count >= minSessions else { continue }  // wait for more history
            guard !inFlight.contains(path) else { continue }
            inFlight.insert(path)
            Task { await synthesize(path: path, entries: entries, projectStore: projectStore, language: language) }
        }
    }

    private func synthesize(
        path: String,
        entries: [(date: Date, summary: SessionSummary)],
        projectStore: ProjectStore,
        language: String
    ) async {
        defer { inFlight.remove(path) }
        guard let project = projectStore.project(for: path) else { return }

        // Split the current brief into the user description + the changelog tail
        // so synthesis replaces ONLY the description and preserves the log.
        let currentBrief = projectStore.brief(for: path)
        let separator = "\n\n---\n"
        let currentDesc: String
        let changelogTail: String
        if let sep = currentBrief.range(of: separator) {
            currentDesc = String(currentBrief[currentBrief.startIndex..<sep.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            changelogTail = String(currentBrief[sep.lowerBound...])
        } else {
            currentDesc = currentBrief.trimmingCharacters(in: .whitespacesAndNewlines)
            changelogTail = ""
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let sessionDTOs = entries
            .sorted { $0.date < $1.date }
            .map { e in
                SynthesizeBriefRequest.SessionDTO(
                    date: df.string(from: e.date),
                    summary: e.summary.summary,
                    lesson: e.summary.lesson.isEmpty ? nil : e.summary.lesson
                )
            }

        let request = SynthesizeBriefRequest(
            language: language,
            project: .init(name: project.displayName),
            sessions: sessionDTOs,
            currentBrief: currentDesc.isEmpty ? nil : currentDesc
        )

        do {
            let resp = try await api.synthesizeBrief(request)
            let overview = resp.overview.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !overview.isEmpty else {
                projectStore.markBriefBackfilled(projectPath: path)
                return
            }
            // Re-check: the user may have hand-edited while the call was in flight.
            guard projectStore.briefDescriptionIsSynthesisWritable(projectPath: path) else {
                projectStore.markBriefBackfilled(projectPath: path)
                return
            }
            projectStore.updateBrief(projectId: path, brief: overview + changelogTail)
            projectStore.markBriefBackfilled(projectPath: path)
            logger.info("Synthesized brief from \(sessionDTOs.count) sessions for \(project.displayName)")
        } catch {
            // Leave un-backfilled so it retries on a later launch.
            logger.warning("Brief synthesis failed for \(project.displayName): \(String(describing: error))")
        }
    }
}
