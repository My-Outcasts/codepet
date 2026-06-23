import Foundation
import Combine
import os

/// Builds the project-aware Dictionary: detects terms in the user's real events,
/// asks the `generateDictionary` Cloud Function for plain-language cards on the
/// ones that are new or have advanced a stage, and merges them into
/// `ProjectDictionaryStore` with their provenance. Mirrors `GuidanceEnricher`.
///
/// Detection and Encountered→Used→Mastered live here (client-side); the server
/// only writes card content. Cards already known at the same stage are NOT
/// re-fetched — their provenance is refreshed locally for free.
@MainActor
final class DictionaryEnricher: ObservableObject {

    private let api: ReflectionAPIClientProtocol
    private let logger = Logger(subsystem: "app.murror.codepet", category: "DictionaryEnricher")

    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    /// Throttle: skip a re-scan if we ran within this window (unless forced).
    private let minInterval: TimeInterval = 60
    private var lastFetchAt: Date?

    init(api: ReflectionAPIClientProtocol) {
        self.api = api
    }

    /// Detect terms and fetch cards for any that are new or freshly advanced.
    func refresh(
        store: ProjectDictionaryStore,
        eventStore: ReflectionEventStore,
        projectStore: ProjectStore?,
        appState: AppState,
        force: Bool = false
    ) async {
        if !force, let last = lastFetchAt, Date().timeIntervalSince(last) < minInterval {
            return
        }
        guard !isLoading else { return }

        let events = eventStore.rawJSONLEvents.map {
            CodeEvent(isoTime: $0.isoTime, text: $0.text, path: $0.path, cwd: $0.cwd)
        }
        let detected = TermDetector.detect(events: events)
        guard !detected.isEmpty else {
            logger.info("no terms detected, skipping dictionary fetch")
            return
        }
        lastFetchAt = Date()

        // Refresh provenance + evolution on every detected term locally (free).
        for term in detected {
            let slug = DictionaryEntry.slug(term.canonical)
            guard var existing = store.entries[slug] else { continue }
            existing.seenIn = badges(from: term)
            existing.lastSeen = term.lastSeen
            existing.firstSeen = min(existing.firstSeen, term.firstSeen)
            existing.evolution = term.evolution
            // Spaced retrieval: re-encountering a term in real code is the
            // strongest, friction-free rep — but the scheduler only counts it
            // if the term was actually due (so a busy session can't fast-track
            // it to mastered). Older entries get seeded with a schedule.
            if let review = existing.review {
                let updated = SpacedScheduler.applyRecurrence(review, now: Date())
                if updated.box > review.box {
                    // A due term genuinely advanced from a real re-encounter —
                    // the delightful "leveled up without a quiz" moment.
                    store.lastPassiveRep = .init(term: existing.term,
                                                 file: existing.seenIn.first?.file ?? "")
                }
                existing.review = updated
            } else {
                existing.review = SpacedScheduler.initial()
            }
            store.entries[slug] = existing
        }

        // A term needs (re)generation when it is unknown, or its stage advanced
        // (so the milestone note and tone are regenerated for the new stage).
        let toGenerate = detected.filter { term in
            guard let existing = store.entries[DictionaryEntry.slug(term.canonical)] else { return true }
            return existing.evolution != term.evolution
        }
        guard !toGenerate.isEmpty else {
            logger.info("dictionary up to date (\(detected.count) terms, 0 to generate)")
            return
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let request = buildRequest(for: toGenerate, projectStore: projectStore, appState: appState)
        do {
            let response = try await api.fetchDictionary(request)
            merge(response: response, detected: toGenerate, into: store)
            logger.info("dictionary fetched: \(response.entries.count) cards, \(response.cacheHits) cache hits")
        } catch {
            lastError = error.localizedDescription
            logger.error("dictionary fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Request / merge

    private func buildRequest(
        for terms: [DetectedTerm],
        projectStore: ProjectStore?,
        appState: AppState
    ) -> GenerateDictionaryRequest {
        let language = appState.uiLanguage.rawValue   // "vi" | "en"

        let termDTOs = terms.map { term in
            GenerateDictionaryRequest.TermDTO(
                term: term.canonical,
                seenIn: badges(from: term).prefix(3).map {
                    GenerateDictionaryRequest.SeenInDTO(
                        file: $0.file,
                        snippet: term.occurrences.first { $0.file.isEmpty == false }?.snippet
                    )
                },
                evolution: term.evolution,
                topicHint: term.topicHint
            )
        }

        return GenerateDictionaryRequest(
            language: language,
            petPersona: buildPetPersona(appState: appState),
            project: primaryProjectDTO(projectStore: projectStore),
            terms: termDTOs
        )
    }

    private func merge(
        response: GenerateDictionaryResponse,
        detected: [DetectedTerm],
        into store: ProjectDictionaryStore
    ) {
        let detectedBySlug = Dictionary(uniqueKeysWithValues:
            detected.map { (DictionaryEntry.slug($0.canonical), $0) })

        for payload in response.entries {
            let slug = DictionaryEntry.slug(payload.term)
            guard let term = detectedBySlug[slug] else { continue }
            let entry = DictionaryEntry(
                term: payload.term,
                title: payload.title,
                topic: payload.topic,
                cardDefinition: payload.cardDefinition,
                whatItReallyMeans: payload.whatItReallyMeans,
                analogy: payload.analogy,
                codeExample: payload.codeExample,
                whenToUse: payload.whenToUse,
                related: payload.related,
                milestoneNote: payload.milestoneNote,
                evolution: term.evolution,
                seenIn: badges(from: term),
                firstSeen: term.firstSeen,
                lastSeen: term.lastSeen,
                generatedAt: Date()
            )
            store.upsert(entry)
        }
    }

    /// File-bearing occurrences, de-duplicated by file, most recent first.
    private func badges(from term: DetectedTerm) -> [SeenRef] {
        var seen = Set<String>()
        var refs: [SeenRef] = []
        for occ in term.occurrences where !occ.file.isEmpty {
            guard !seen.contains(occ.file) else { continue }
            seen.insert(occ.file)
            refs.append(SeenRef(file: occ.file, date: occ.date))
        }
        return refs
    }

    private func primaryProjectDTO(projectStore: ProjectStore?) -> GenerateDictionaryRequest.ProjectDTO? {
        guard let primary = projectStore?.projects.values.sorted(by: { $0.lastSeenAt > $1.lastSeenAt }).first
        else { return nil }
        let tags = ProjectSignals.inferTags(from: primary.id, brief: primary.brief).map(\.rawValue)
        return GenerateDictionaryRequest.ProjectDTO(
            name: primary.displayName,
            brief: primary.brief.isEmpty ? nil : primary.brief,
            tags: tags.isEmpty ? nil : tags
        )
    }

    /// Build the pet persona DTO from the active character (same shape as
    /// `GuidanceEnricher.buildPetPersona`).
    private func buildPetPersona(appState: AppState) -> SummarizeTurnRequest.PetPersonaDTO? {
        guard let character = PetCharacter.all[appState.activeChar] else { return nil }
        return SummarizeTurnRequest.PetPersonaDTO(
            id: character.id,
            name: character.name,
            personality: character.personality,
            domain: character.domain,
            voiceGuide: character.voiceGuide,
            lensGuide: character.lensGuide,
            emotionalTriggers: character.emotionalTriggers,
            metaphorFamily: character.metaphorFamily,
            signatureEmojis: character.signatureEmojis
        )
    }
}
