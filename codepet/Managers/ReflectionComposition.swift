import Foundation
import Combine

// MARK: - Chat context composition

extension ReflectionComposition {

    /// Flattens a `Session` into the `ChatSessionRequest.SessionContextDTO` used
    /// when sending context to the chat Cloud Function.
    static func makeChatContext(
        for session: Session,
        userBrief: String?
    ) -> ChatSessionRequest.SessionContextDTO {
        let summaryDTO: ChatSessionRequest.SessionContextDTO.SummaryDTO? = session.summary.map {
            ChatSessionRequest.SessionContextDTO.SummaryDTO(
                summary: $0.summary,
                lesson: $0.lesson
            )
        }

        let turnDTOs: [ChatSessionRequest.SessionContextDTO.TurnDTO] = session.turns.map { turn in
            let duration: Int?
            if let ended = turn.endedAt {
                duration = Int(ended.timeIntervalSince(turn.startedAt) / 60)
            } else {
                duration = nil
            }

            let events: [SummarizeTurnRequest.EventDTO] = turn.rawEvents.map { e in
                SummarizeTurnRequest.EventDTO(
                    time: e.time,
                    tool: Self.extractTool(from: e.text),
                    path: Self.extractPath(from: e.text),
                    text: e.text
                )
            }

            return ChatSessionRequest.SessionContextDTO.TurnDTO(
                prompt: turn.prompt,
                whatYouWanted: turn.narrative?.whatYouWanted,
                whatHappened: turn.narrative?.whatHappened,
                lesson: turn.narrative?.lesson,
                durationMinutes: duration,
                events: events
            )
        }

        let brief = userBrief.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }

        return ChatSessionRequest.SessionContextDTO(
            userBrief: brief,
            summary: summaryDTO,
            turns: turnDTOs
        )
    }

    // MARK: - Private helpers (mirrors NarrativeEnricher logic)

    private static func extractTool(from text: String) -> String {
        if text.hasPrefix("Bash:") { return "Bash" }
        return text.components(separatedBy: " ").first ?? text
    }

    private static func extractPath(from text: String) -> String? {
        let parts = text.components(separatedBy: " ")
        guard parts.count > 1 else { return nil }
        return parts.dropFirst().joined(separator: " ")
    }
}

// MARK: - ReflectionComposition class

@MainActor
final class ReflectionComposition: ObservableObject {
    let objectWillChange = PassthroughSubject<Void, Never>()

    let eventStore: ReflectionEventStore
    let narrativeStore: NarrativeStore
    let summaryStore: SessionSummaryStore
    let endStore: SessionEndStore
    let enricher: NarrativeEnricher
    let sessionEnricher: SessionSummaryEnricher
    let api: ReflectionAPIClient

    init(language: String = "en") {
        let events = ReflectionEventStore()
        let narratives = NarrativeStore()
        let summaries = SessionSummaryStore()
        let ends = SessionEndStore()
        let api = ReflectionAPIClient()
        self.eventStore = events
        self.narrativeStore = narratives
        self.summaryStore = summaries
        self.endStore = ends
        self.api = api
        self.enricher = NarrativeEnricher(api: api, store: narratives, language: language)
        self.sessionEnricher = SessionSummaryEnricher(api: api, store: summaries, language: language)
    }

    /// Update the language used for all future AI-generated narratives and summaries.
    func updateLanguage(_ lang: AppLanguage) {
        let code = lang.rawValue   // "vi" or "en"
        enricher.language = code
        sessionEnricher.language = code
    }

    func start() {
        eventStore.start()
        narrativeStore.start()
        summaryStore.start()
        endStore.start()
    }
}
