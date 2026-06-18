import Foundation
import CryptoKit

/// Input to the assembler. Source events from `events.jsonl` and `narratives.jsonl`
/// are converted to this shape before assembly so the assembler stays pure.
struct AssemblerInput {
    enum Kind {
        case prompt(text: String)
        case tool(text: String)
        case summary(text: String)
    }
    let kind: Kind
    let isoTime: String           // raw ISO 8601 — used for turn_id
    let sessionId: String
    let cwd: String                // working directory — used for project detection
    let path: String               // file path from tool events — used for project detection

    init(kind: Kind, isoTime: String, sessionId: String, cwd: String = "", path: String = "") {
        self.kind = kind
        self.isoTime = isoTime
        self.sessionId = sessionId
        self.cwd = cwd
        self.path = path
    }
}

enum TurnAssembler {

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Group inputs into Turns. Pure — no I/O.
    /// `failedTurns` carries the in-memory enrichment failure map from
    /// `NarrativeEnricher` so the UI can render the failure UI instead of an
    /// indefinite "summarizing" skeleton when the cloud function call fails.
    static func assemble(
        inputs: [AssemblerInput],
        now: Date,
        narratives: [String: Narrative],
        failedTurns: [String: FailureReason] = [:]
    ) -> [Turn] {
        let sorted = inputs.sorted { lhs, rhs in
            if lhs.sessionId != rhs.sessionId { return lhs.sessionId < rhs.sessionId }
            return lhs.isoTime < rhs.isoTime
        }

        var turns: [Turn] = []
        var sessionGroups: [String: [AssemblerInput]] = [:]
        for input in sorted { sessionGroups[input.sessionId, default: []].append(input) }

        for (sessionId, events) in sessionGroups {
            turns.append(contentsOf: assembleSession(
                sessionId: sessionId,
                events: events,
                now: now,
                narratives: narratives,
                failedTurns: failedTurns
            ))
        }

        return turns.sorted { $0.startedAt > $1.startedAt }
    }

    private static func assembleSession(
        sessionId: String,
        events: [AssemblerInput],
        now: Date,
        narratives: [String: Narrative],
        failedTurns: [String: FailureReason]
    ) -> [Turn] {
        var turns: [Turn] = []

        // Drop summary events that arrive before any prompt.
        var pendingPrompt: AssemblerInput? = nil
        var pendingTools: [AssemblerInput] = []

        func flushAsOrphan() {
            guard let prompt = pendingPrompt,
                  case .prompt(let text) = prompt.kind,
                  let started = isoFormatter.date(from: prompt.isoTime) else { return }
            turns.append(makeTurn(
                prompt: text,
                started: started,
                ended: nil,
                tools: pendingTools,
                sessionId: sessionId,
                promptISO: prompt.isoTime,
                promptCwd: prompt.cwd,
                narratives: narratives,
                failedTurns: failedTurns,
                forceState: .pendingOrphan
            ))
            pendingPrompt = nil
            pendingTools = []
        }

        for input in events {
            switch input.kind {
            case .prompt:
                if pendingPrompt != nil {
                    flushAsOrphan()  // previous prompt orphaned by new prompt
                }
                pendingPrompt = input
                pendingTools = []
            case .tool:
                if pendingPrompt != nil { pendingTools.append(input) }
            case .summary:
                guard let prompt = pendingPrompt,
                      case .prompt(let promptText) = prompt.kind,
                      let started = isoFormatter.date(from: prompt.isoTime),
                      let ended = isoFormatter.date(from: input.isoTime) else { continue }
                turns.append(makeTurn(
                    prompt: promptText,
                    started: started,
                    ended: ended,
                    tools: pendingTools,
                    sessionId: sessionId,
                    promptISO: prompt.isoTime,
                    promptCwd: prompt.cwd,
                    narratives: narratives,
                    failedTurns: failedTurns,
                    forceState: nil
                ))
                pendingPrompt = nil
                pendingTools = []
            }
        }

        // Trailing prompt with no summary
        if let prompt = pendingPrompt,
           case .prompt(let text) = prompt.kind,
           let started = isoFormatter.date(from: prompt.isoTime) {
            let age = now.timeIntervalSince(started)
            // A prompt with no Stop event is only treated as abandoned after 30
            // minutes — matching the documented contract on Turn.pendingOrphan
            // ("no Stop event after 30 min") and SessionSummaryEnricher's idle
            // threshold. (Was incorrectly 5 min after an unrelated refactor.)
            let orphanThreshold: TimeInterval = 30 * 60
            let state: TurnState = age > orphanThreshold ? .pendingOrphan : .pending
            turns.append(makeTurn(
                prompt: text,
                started: started,
                ended: nil,
                tools: pendingTools,
                sessionId: sessionId,
                promptISO: prompt.isoTime,
                promptCwd: prompt.cwd,
                narratives: narratives,
                failedTurns: failedTurns,
                forceState: state
            ))
        }

        return turns
    }

    private static func makeTurn(
        prompt: String,
        started: Date,
        ended: Date?,
        tools: [AssemblerInput],
        sessionId: String,
        promptISO: String,
        promptCwd: String = "",
        narratives: [String: Narrative],
        failedTurns: [String: FailureReason],
        forceState: TurnState?
    ) -> Turn {
        let id = Turn.makeID(sessionId: sessionId, promptISO: promptISO)
        let narrative = narratives[id]

        // Build rawEvents first so we can check for write operations
        let rawEvents: [CapturedEvent] = tools.map { input in
            let displayTime = displayHHmm(input.isoTime)
            let text: String
            if case .tool(let t) = input.kind { text = t } else { text = "" }
            let seed = "\(sessionId)|\(input.isoTime)|\(text)"
            return CapturedEvent(
                id: deterministicID(seed: seed),
                time: displayTime,
                source: .claudeCode,
                text: text,
                sessionId: sessionId,
                cwd: input.cwd.isEmpty ? nil : input.cwd,
                path: input.path.isEmpty ? nil : input.path
            )
        }

        // Check if any events are write operations (Edit, Write, non-trivial Bash).
        // Read-only turns (git status, ls, cat) skip summarization.
        let hasWrites = rawEvents.contains { event in
            let text = event.text.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("Edit") || text.hasPrefix("Write") { return true }
            if text.hasPrefix("Bash:") || text.hasPrefix("Bash(") {
                return !Turn.isReadOnlyBash(text)
            }
            return false
        }

        let state: TurnState
        if let forced = forceState {
            state = forced
        } else if narrative != nil {
            state = .ready
        } else if ended != nil, let reason = failedTurns[id] {
            state = .failed(reason: reason)
        } else if ended != nil {
            // Only trigger summarization for turns with actual write operations.
            // Read-only turns (git status, ls) skip straight to ready.
            state = hasWrites ? .summarizing : .ready
        } else {
            state = .pending
        }

        return Turn(
            id: id,
            sessionId: sessionId,
            startedAt: started,
            endedAt: ended,
            prompt: prompt,
            rawEvents: rawEvents,
            narrative: narrative,
            state: state,
            cwd: promptCwd.isEmpty ? nil : promptCwd
        )
    }

    private static func deterministicID(seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func displayHHmm(_ iso: String) -> String {
        guard let date = isoFormatter.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

extension TurnAssembler {
    /// A session is cut whenever two consecutive turns are separated by more
    /// than this much idle wall-clock time, measured from the previous turn's
    /// end to the next turn's start. The Claude Code CLI keeps one session id
    /// for as long as its process lives, so a terminal left open all day would
    /// otherwise fuse a morning and an evening of unrelated work into one giant
    /// record. 45 min keeps a coffee break or a long build/commit in one
    /// session but splits lunch or an afternoon away into a fresh one. It sits
    /// safely above SessionSummaryEnricher's 30-min idle threshold, so any
    /// split-off earlier segment is already idle enough to auto-summarize.
    static let sessionIdleSplitGap: TimeInterval = 45 * 60

    /// Group turns into Sessions. Each session sorted oldest-first internally.
    /// Sessions sorted by their newest turn's startedAt descending.
    ///
    /// Turns are first grouped by their CLI session id, then each group is
    /// split on idle gaps (see `sessionIdleSplitGap`) so a single long-lived
    /// CLI session becomes one CodePet session per burst of real work.
    static func assembleSessions(
        turns: [Turn],
        summaries: [String: SessionSummary]
    ) -> [Session] {
        var bySession: [String: [Turn]] = [:]
        for turn in turns { bySession[turn.sessionId, default: []].append(turn) }

        var sessions: [Session] = []
        for (sessionId, sessionTurns) in bySession {
            let chronological = sessionTurns.sorted { $0.startedAt < $1.startedAt }

            // Cut into segments wherever the idle gap exceeds the threshold.
            var segments: [[Turn]] = []
            var current: [Turn] = []
            for turn in chronological {
                if let last = current.last {
                    let prevEnd = last.endedAt ?? last.startedAt
                    if turn.startedAt.timeIntervalSince(prevEnd) > sessionIdleSplitGap {
                        segments.append(current)
                        current = []
                    }
                }
                current.append(turn)
            }
            if !current.isEmpty { segments.append(current) }

            for (index, segment) in segments.enumerated() {
                // The first segment keeps the raw CLI id so its existing summary
                // and chat thread survive; later segments get a stable suffixed
                // id (the past is immutable, so a turn never changes segments
                // retroactively) and earn their own summary + chat on demand.
                let segmentId = index == 0 ? sessionId : "\(sessionId)#\(index + 1)"
                sessions.append(makeSession(id: segmentId, chronological: segment, summaries: summaries))
            }
        }

        return sessions
            .sorted { ($0.turns.last?.startedAt ?? .distantPast) > ($1.turns.last?.startedAt ?? .distantPast) }
    }

    private static func makeSession(
        id: String,
        chronological: [Turn],
        summaries: [String: SessionSummary]
    ) -> Session {
        let earliest = chronological.first?.startedAt ?? Date()
        let latestEnded = chronological.compactMap { $0.endedAt }.max()
        // Infer project path: prefer the prompt's cwd (available immediately
        // on the first poll, before any tool events arrive), fall back to
        // the first tool event that has a cwd.
        let projectPath = chronological.lazy.compactMap(\.cwd).first
            ?? chronological.lazy.flatMap(\.rawEvents).compactMap(\.cwd).first
        // Collect unique file paths from tool events — used to disambiguate
        // multi-project workspaces (e.g. ~/Test folder with yoga-site/ + sprout/)
        let filePaths = Array(Set(
            chronological.lazy
                .flatMap(\.rawEvents)
                .compactMap(\.path)
                .filter { !$0.isEmpty }
        ))
        return Session(
            id: id,
            turns: chronological,
            startedAt: earliest,
            endedAt: latestEnded,
            summary: summaries[id],
            projectPath: projectPath,
            filePaths: filePaths
        )
    }
}
