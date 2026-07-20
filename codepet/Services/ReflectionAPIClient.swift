import Foundation
import FirebaseAuth

// MARK: - DTOs

struct SummarizeTurnRequest: Codable {
    let turnId: String
    let sessionId: String
    let language: String       // "vi" | "en"
    let prompt: String
    let events: [EventDTO]
    let rawSummary: String
    let petPersona: PetPersonaDTO?
    let userBrief: String?     // user's project brief from welcome screen
    let petMemory: String?     // compact cross-session memory for personalization

    struct EventDTO: Codable {
        let time: String       // "HH:mm"
        let tool: String
        let path: String?
        let text: String?
    }

    struct PetPersonaDTO: Codable {
        let id: String           // "byte"
        let name: String         // "Byte"
        let personality: String  // "glitchy, chaotic, thinks in fragments"
        let domain: String       // "Data / ML"
        let voiceGuide: String   // how they talk — rhythm, humor, style
        let lensGuide: String    // what they notice and advise on
        let emotionalTriggers: String  // what excites vs. concerns them
        let metaphorFamily: String     // preferred metaphor domains
        let signatureEmojis: String    // 3-4 emojis they gravitate toward

        enum CodingKeys: String, CodingKey {
            case id, name, personality, domain
            case voiceGuide = "voice_guide"
            case lensGuide = "lens_guide"
            case emotionalTriggers = "emotional_triggers"
            case metaphorFamily = "metaphor_family"
            case signatureEmojis = "signature_emojis"
        }
    }

    enum CodingKeys: String, CodingKey {
        case turnId = "turn_id"
        case sessionId = "session_id"
        case language
        case prompt
        case events
        case rawSummary = "raw_summary"
        case petPersona = "pet_persona"
        case userBrief = "user_brief"
        case petMemory = "pet_memory"
    }
}

struct SummarizeTurnResponse: Codable {
    let turnId: String
    let narrative: NarrativePayload
    let model: String
    let cacheHit: Bool

    struct DetectedSkillDTO: Codable, Equatable {
        let skillId: String
        let confidence: String  // "strong" | "weak"
        let evidence: String

        enum CodingKeys: String, CodingKey {
            case skillId = "skill_id"
            case confidence, evidence
        }
    }

    struct NarrativePayload: Codable, Equatable {
        let title: String
        let whatYouWanted: String
        let whatHappened: String
        let lesson: String
        let nextSteps: String?
        let mood: String?
        let detectedSkills: [DetectedSkillDTO]?

        enum CodingKeys: String, CodingKey {
            case title
            case whatYouWanted = "what_you_wanted"
            case whatHappened = "what_happened"
            case lesson
            case nextSteps = "next_steps"
            case mood
            case detectedSkills = "detected_skills"
        }
    }

    enum CodingKeys: String, CodingKey {
        case turnId = "turn_id"
        case narrative
        case model
        case cacheHit = "cache_hit"
    }
}

struct SummarizeTurnError: Codable, Error {
    let error: String
    let resetAt: String?
    let limit: Int?
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case error
        case resetAt = "reset_at"
        case limit
        case detail
    }
}

// MARK: - Session DTOs

struct SummarizeSessionRequest: Codable {
    let sessionId: String
    let language: String
    let turns: [TurnDTO]
    let petPersona: SummarizeTurnRequest.PetPersonaDTO?
    let userBrief: String?
    let petMemory: String?

    struct TurnDTO: Codable {
        let prompt: String
        let whatYouWanted: String?
        let whatHappened: String?
        let durationMinutes: Int?

        enum CodingKeys: String, CodingKey {
            case prompt
            case whatYouWanted = "what_you_wanted"
            case whatHappened = "what_happened"
            case durationMinutes = "duration_minutes"
        }
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case language
        case turns
        case petPersona = "pet_persona"
        case userBrief = "user_brief"
        case petMemory = "pet_memory"
    }
}

struct SummarizeSessionResponse: Codable {
    let sessionId: String
    let summary: SummaryPayload
    let model: String

    struct SummaryPayload: Codable, Equatable {
        let summary: String
        let lesson: String
        let briefUpdate: String?
        let projectOverview: String?
        /// Process-literacy observations (the "growth edge" + its structured
        /// signal). Optional with a default so existing call sites and cached
        /// payloads keep working; absent until the server function is redeployed
        /// with the growth_signals contract.
        var growthSignals: [AgencySignalDTO]? = nil

        enum CodingKeys: String, CodingKey {
            case summary, lesson
            case briefUpdate = "brief_update"
            case projectOverview = "project_overview"
            case growthSignals = "growth_signals"
        }
    }

    /// One agency/process observation as returned by the session summary.
    /// `observation` is the human-facing growth-edge sentence; the rest is the
    /// structured signal the Learner Model will later aggregate.
    struct AgencySignalDTO: Codable, Equatable {
        let observation: String
        let axis: String        // "agency" | "comprehension"
        let signal: String      // scoping|prompting|verification|direction|iteration|context
        let valence: String     // "growth" | "strength"
        let evidence: String
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case summary
        case model
    }
}

// MARK: - Chat DTOs

struct ChatSessionRequest: Codable {
    let sessionId: String
    let language: String
    let petPersona: SummarizeTurnRequest.PetPersonaDTO?
    let sessionContext: SessionContextDTO
    let history: [ChatMessageDTO]
    let userMessage: String

    struct SessionContextDTO: Codable {
        let userBrief: String?
        let summary: SummaryDTO?
        let turns: [TurnDTO]

        struct SummaryDTO: Codable {
            let summary: String
            let lesson: String
        }

        struct TurnDTO: Codable {
            let prompt: String
            let whatYouWanted: String?
            let whatHappened: String?
            let lesson: String?
            let durationMinutes: Int?
            let events: [SummarizeTurnRequest.EventDTO]

            enum CodingKeys: String, CodingKey {
                case prompt
                case whatYouWanted = "what_you_wanted"
                case whatHappened = "what_happened"
                case lesson
                case durationMinutes = "duration_minutes"
                case events
            }
        }

        enum CodingKeys: String, CodingKey {
            case userBrief = "user_brief"
            case summary
            case turns
        }
    }

    struct ChatMessageDTO: Codable {
        let role: String   // "user" | "pet"
        let text: String
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case language
        case petPersona = "pet_persona"
        case sessionContext = "session_context"
        case history
        case userMessage = "user_message"
    }
}

// MARK: - Guidance DTOs

struct GenerateGuidanceRequest: Codable {
    let language: String       // "vi" | "en"
    let petPersona: SummarizeTurnRequest.PetPersonaDTO?
    let recentNarratives: [NarrativeSummaryDTO]
    let skillProgress: [SkillProgressDTO]?
    let petMemory: String?
    let expertKnowledge: [ExpertKnowledgeDTO]?
    /// The focus shown last time, so the server can check whether the user
    /// acted on it and decide to continue, complete + advance, or start new.
    let previousFocus: PreviousFocusDTO?

    struct PreviousFocusDTO: Codable {
        let project: String?
        let move: String
        let repeatCount: Int

        enum CodingKeys: String, CodingKey {
            case project, move
            case repeatCount = "repeat_count"
        }
    }

    struct ExpertKnowledgeDTO: Codable {
        let expertName: String
        let kind: String           // "principle", "patternResponse", "codeWisdom", "mindset"
        let advice: String
        let oneLiner: String

        enum CodingKeys: String, CodingKey {
            case expertName = "expert_name"
            case kind, advice
            case oneLiner = "one_liner"
        }
    }

    struct NarrativeSummaryDTO: Codable {
        let title: String
        let whatHappened: String
        let lesson: String?
        let mood: String?
        /// Display name of the project this narrative belongs to, so guidance
        /// can attribute its evidence to a specific project.
        let project: String?

        enum CodingKeys: String, CodingKey {
            case title
            case whatHappened = "what_happened"
            case lesson, mood, project
        }
    }

    struct SkillProgressDTO: Codable {
        let skillId: String
        let practiceCount: Int
        let isMastered: Bool

        enum CodingKeys: String, CodingKey {
            case skillId = "skill_id"
            case practiceCount = "practice_count"
            case isMastered = "is_mastered"
        }
    }

    enum CodingKeys: String, CodingKey {
        case language
        case petPersona = "pet_persona"
        case recentNarratives = "recent_narratives"
        case skillProgress = "skill_progress"
        case petMemory = "pet_memory"
        case expertKnowledge = "expert_knowledge"
        case previousFocus = "previous_focus"
    }
}

struct GenerateGuidanceResponse: Codable {
    let guidance: GuidancePayload
    let model: String
    let generatedAt: String

    struct GuidancePayload: Codable, Equatable {
        let headline: String
        let project: String?
        let strength: String
        let gap: String?
        let move: String
        let status: String        // "new" | "continued" | "completed"
        let mood: String

        enum CodingKeys: String, CodingKey {
            case headline, project, strength, gap, move, status, mood
        }
    }

    enum CodingKeys: String, CodingKey {
        case guidance, model
        case generatedAt = "generated_at"
    }
}

// MARK: - Plan DTOs (Project Health action plans)

/// Request for the generatePlan Cloud Function — a per-section action plan.
struct GeneratePlanRequest: Codable {
    let language: String        // "vi" | "en"
    let project: ProjectDTO
    let section: SectionDTO
    /// Optional recent narratives for personalization (reuses guidance's DTO).
    let recentNarratives: [GenerateGuidanceRequest.NarrativeSummaryDTO]?

    struct ProjectDTO: Codable {
        let name: String
        let stage: String       // ProjectStage rawValue
        let brief: String
        let tags: [String]      // ProjectTag rawValues
        let domains: [String]   // ProjectDomain rawValues
    }

    struct SectionDTO: Codable {
        let ruleId: String
        let title: String
        let pillar: String          // HealthPillar rawValue
        let currentState: String    // "missing" | "passed" | "attested"

        enum CodingKeys: String, CodingKey {
            case ruleId = "rule_id"
            case title, pillar
            case currentState = "current_state"
        }
    }

    enum CodingKeys: String, CodingKey {
        case language, project, section
        case recentNarratives = "recent_narratives"
    }
}

/// Response from the generatePlan Cloud Function. `locked_step_count` and the
/// empty `detail` on locked steps reflect server-side paywall gating.
struct GeneratePlanResponse: Codable {
    let plan: PlanPayload
    let tier: String            // "preview" | "full"
    let lockedStepCount: Int
    let model: String
    let generatedAt: String

    struct PlanPayload: Codable {
        let summary: String
        let steps: [StepPayload]
        let pitfalls: [String]?
        let estEffort: String

        enum CodingKeys: String, CodingKey {
            case summary, steps, pitfalls
            case estEffort = "est_effort"
        }
    }

    struct StepPayload: Codable {
        let title: String
        let detail: String      // "" when locked (free tier)
        let doneWhen: String

        enum CodingKeys: String, CodingKey {
            case title, detail
            case doneWhen = "done_when"
        }
    }

    enum CodingKeys: String, CodingKey {
        case plan, tier, model
        case lockedStepCount = "locked_step_count"
        case generatedAt = "generated_at"
    }
}

// MARK: - Distill Reference DTOs

/// Request for the distillReference Cloud Function — turns a recommended reading
/// resource into a few concrete, project-specific principles for the coding agent.
struct DistillReferenceRequest: Codable {
    let language: String        // "vi" | "en"
    let project: ProjectDTO
    let resource: ResourceDTO

    struct ProjectDTO: Codable {
        let name: String
        let stage: String       // ProjectStage rawValue
        let brief: String
        let tags: [String]      // ProjectTag rawValues
        let domains: [String]   // ProjectDomain rawValues
    }

    struct ResourceDTO: Codable {
        let title: String
        let author: String
        let kind: String
        let why: String
    }
}

/// Response from distillReference: a few one-sentence directives.
struct DistillReferenceResponse: Codable {
    let principles: [String]
    let model: String
    let generatedAt: String

    enum CodingKeys: String, CodingKey {
        case principles, model
        case generatedAt = "generated_at"
    }
}

// MARK: - Dictionary DTOs (project-aware personal dictionary)

/// Request for the generateDictionary Cloud Function — turns terms detected in
/// the user's own code into plain-language, pet-voiced cards. Detection and the
/// Encountered→Used→Mastered stage live client-side; the server generates only
/// the card content (and a milestone note when a term is freshly mastered).
struct GenerateDictionaryRequest: Codable {
    let language: String            // "vi" | "en"
    let petPersona: SummarizeTurnRequest.PetPersonaDTO?
    let project: ProjectDTO?
    let terms: [TermDTO]

    struct ProjectDTO: Codable {
        let name: String
        let brief: String?
        let tags: [String]?         // ProjectTag rawValues
    }

    struct SeenInDTO: Codable {
        let file: String            // e.g. "LoginView.swift"
        let snippet: String?        // short excerpt (server caps at 200 chars)
    }

    struct TermDTO: Codable {
        let term: String            // literal token, e.g. "OAuth"
        let seenIn: [SeenInDTO]?
        let evolution: String?      // "encountered" | "used" | "mastered"
        let topicHint: String?      // "frameworks" | "patterns" | "tools" | ...

        enum CodingKeys: String, CodingKey {
            case term
            case seenIn = "seen_in"
            case evolution
            case topicHint = "topic_hint"
        }
    }

    enum CodingKeys: String, CodingKey {
        case language, project, terms
        case petPersona = "pet_persona"
    }
}

/// Response from generateDictionary: one card per requested term (same order),
/// each echoing its `term` token for client-side mapping back to provenance.
struct GenerateDictionaryResponse: Codable {
    let entries: [EntryPayload]
    let model: String
    let generatedAt: String
    let cacheHits: Int

    struct EntryPayload: Codable, Equatable {
        let term: String
        let title: String
        let topic: String           // one of the dynamic topic groups
        let cardDefinition: String
        let whatItReallyMeans: String
        let analogy: String
        let codeExample: String     // "" if none
        let whenToUse: String       // "" if N/A
        let related: [String]
        let milestoneNote: String   // "" unless freshly mastered

        enum CodingKeys: String, CodingKey {
            case term, title, topic, analogy, related
            case cardDefinition = "card_definition"
            case whatItReallyMeans = "what_it_really_means"
            case codeExample = "code_example"
            case whenToUse = "when_to_use"
            case milestoneNote = "milestone_note"
        }
    }

    enum CodingKeys: String, CodingKey {
        case entries, model
        case generatedAt = "generated_at"
        case cacheHits = "cache_hits"
    }
}

// MARK: - Narrative Stream DTOs

enum NarrativeStreamEvent: Equatable {
    /// The SSE connection opened — show "generating" UI immediately.
    case started
    /// A chunk of partial JSON from the tool_use input_json_delta.
    case jsonDelta(String)
    /// The final complete narrative.
    case done(narrative: SummarizeTurnResponse.NarrativePayload, model: String, cacheHit: Bool)
}

enum SessionSummaryStreamEvent: Equatable {
    case started
    case jsonDelta(String)
    case done(summary: SummarizeSessionResponse.SummaryPayload, model: String, briefUpdate: String?, projectOverview: String?)
}

enum ChatStreamEvent: Equatable {
    case delta(String)
    case done(model: String, cacheHit: Bool)
}

// MARK: - Client

protocol ReflectionAPIClientProtocol {
    func summarizeTurn(_ request: SummarizeTurnRequest) async throws -> SummarizeTurnResponse
    func summarizeTurnStream(_ request: SummarizeTurnRequest) -> AsyncThrowingStream<NarrativeStreamEvent, Error>
    func summarizeSession(_ request: SummarizeSessionRequest) async throws -> SummarizeSessionResponse
    func summarizeSessionStream(_ request: SummarizeSessionRequest) -> AsyncThrowingStream<SessionSummaryStreamEvent, Error>
    func chatSessionStream(_ request: ChatSessionRequest) -> AsyncThrowingStream<ChatStreamEvent, Error>
    func fetchGuidance(_ request: GenerateGuidanceRequest) async throws -> GenerateGuidanceResponse
    func fetchPlan(_ request: GeneratePlanRequest) async throws -> GeneratePlanResponse
    func fetchReferenceDistillation(_ request: DistillReferenceRequest) async throws -> DistillReferenceResponse
    func synthesizeBrief(_ request: SynthesizeBriefRequest) async throws -> SynthesizeBriefResponse
    func fetchDictionary(_ request: GenerateDictionaryRequest) async throws -> GenerateDictionaryResponse
    func enrichBrief(_ brief: CompanyBrief) async throws -> CompanyBrief
    func scaffoldRoadmap(brief: CompanyBrief, stage: ProjectStage, departments: [RoadmapDeptInput]) async throws -> [RoadmapTask]
}

extension ReflectionAPIClientProtocol {
    /// Default so existing conformers (e.g. test mocks) don't have to implement
    /// plan generation. The real client overrides this.
    func fetchPlan(_ request: GeneratePlanRequest) async throws -> GeneratePlanResponse {
        throw ReflectionAPIError.malformedResponse
    }
    /// Default so existing conformers (e.g. test mocks) don't have to implement
    /// reference distillation. The real client overrides this.
    func fetchReferenceDistillation(_ request: DistillReferenceRequest) async throws -> DistillReferenceResponse {
        throw ReflectionAPIError.malformedResponse
    }
    /// Default so existing conformers (e.g. test mocks) don't have to implement
    /// brief synthesis. The real client overrides this.
    func synthesizeBrief(_ request: SynthesizeBriefRequest) async throws -> SynthesizeBriefResponse {
        throw ReflectionAPIError.malformedResponse
    }
    /// Default so existing conformers (e.g. test mocks) don't have to implement
    /// dictionary generation. The real client overrides this.
    func fetchDictionary(_ request: GenerateDictionaryRequest) async throws -> GenerateDictionaryResponse {
        throw ReflectionAPIError.malformedResponse
    }
    /// Default so existing conformers (e.g. test mocks) don't have to implement
    /// brief enrichment. The real client overrides this.
    func enrichBrief(_ brief: CompanyBrief) async throws -> CompanyBrief {
        throw ReflectionAPIError.malformedResponse
    }
    /// Default so existing conformers (e.g. test mocks) don't have to implement
    /// roadmap scaffolding. The real client overrides this.
    func scaffoldRoadmap(brief: CompanyBrief, stage: ProjectStage, departments: [RoadmapDeptInput]) async throws -> [RoadmapTask] {
        throw ReflectionAPIError.malformedResponse
    }
}

// MARK: - Synthesize Brief DTOs

/// Request to the synthesizeBrief Cloud Function: a project's full session
/// history (already-generated summaries) → one complete project description.
struct SynthesizeBriefRequest: Codable {
    let language: String        // "vi" | "en"
    let project: ProjectDTO
    let sessions: [SessionDTO]
    let currentBrief: String?   // user's current description (for continuity)

    struct ProjectDTO: Codable {
        let name: String
    }

    struct SessionDTO: Codable {
        let date: String?       // "yyyy-MM-dd"
        let summary: String
        let lesson: String?
    }

    enum CodingKeys: String, CodingKey {
        case language, project, sessions
        case currentBrief = "current_brief"
    }
}

struct SynthesizeBriefResponse: Codable {
    let overview: String
    let model: String
    let generatedAt: String

    enum CodingKeys: String, CodingKey {
        case overview, model
        case generatedAt = "generated_at"
    }
}

// MARK: - Enrich Brief DTOs

/// Request/response for the enrichBrief Cloud Function — takes the founder's
/// self-described `CompanyBrief` and returns a server-enriched version (adds
/// `summary`/`categories`/etc. where the model has enough signal).
struct EnrichBriefRequest: Codable { let brief: CompanyBrief }
struct EnrichBriefResponse: Codable { let brief: CompanyBrief }

// MARK: - Scaffold Roadmap DTOs

/// One department fed to the scaffoldRoadmap Cloud Function — its health-pillar
/// key, display name, and the expertise blurb that grounds the generated tasks.
struct RoadmapDeptInput: Codable { let key: String; let name: String; let expertise: String }

private struct ScaffoldRoadmapRequest: Codable { let brief: CompanyBrief; let stage: String; let departments: [RoadmapDeptInput] }
private struct ScaffoldRoadmapResponse: Codable {
    struct Dept: Codable { let key: String; let tasks: [Task] }
    struct Task: Codable { let title: String; let detail: String; let who: String; let kind: String }
    let departments: [Dept]
}

enum ReflectionAPIError: Error {
    case notSignedIn
    case http(status: Int, body: SummarizeTurnError?)
    case malformedResponse
    case network(Error)
}

@MainActor
final class ReflectionAPIClient: ReflectionAPIClientProtocol {

    static let endpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/summarizeTurn")!
    private static let sessionEndpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/summarizeSession")!
    private static let chatEndpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/chatSession")!
    private static let guidanceEndpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/generateGuidance")!
    private static let planEndpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/generatePlan")!
    private static let distillEndpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/distillReference")!
    private static let synthesizeBriefEndpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/synthesizeBrief")!
    private static let dictionaryEndpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/generateDictionary")!
    private static let enrichBriefEndpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/enrichBrief")!
    private static let scaffoldRoadmapEndpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/scaffoldRoadmap")!

    private let session: URLSession
    private let authTokenProvider: () async throws -> String

    init(
        session: URLSession = .shared,
        authTokenProvider: (() async throws -> String)? = nil
    ) {
        self.session = session
        self.authTokenProvider = authTokenProvider ?? {
            guard let user = Auth.auth().currentUser else {
                throw ReflectionAPIError.notSignedIn
            }
            do {
                return try await user.getIDToken()
            } catch {
                throw ReflectionAPIError.network(error)
            }
        }
    }

    func summarizeTurn(_ request: SummarizeTurnRequest) async throws -> SummarizeTurnResponse {
        let token = try await authTokenProvider()

        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ReflectionAPIError.malformedResponse
        }

        if http.statusCode == 200 {
            do {
                return try JSONDecoder().decode(SummarizeTurnResponse.self, from: data)
            } catch {
                throw ReflectionAPIError.malformedResponse
            }
        }

        let parsed = try? JSONDecoder().decode(SummarizeTurnError.self, from: data)
        throw ReflectionAPIError.http(status: http.statusCode, body: parsed)
    }

    func summarizeTurnStream(_ request: SummarizeTurnRequest) -> AsyncThrowingStream<NarrativeStreamEvent, Error> {
        let capturedSession = session
        let capturedAuthTokenProvider = authTokenProvider
        // Append ?stream=true to the endpoint URL
        var streamURL = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        streamURL.queryItems = [URLQueryItem(name: "stream", value: "true")]
        let url = streamURL.url!

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let token = try await capturedAuthTokenProvider()

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, response) = try await capturedSession.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw ReflectionAPIError.malformedResponse
                    }

                    if http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        let parsed = try? JSONDecoder().decode(SummarizeTurnError.self, from: data)
                        throw ReflectionAPIError.http(status: http.statusCode, body: parsed)
                    }

                    // SSE connection opened — signal generating state
                    continuation.yield(.started)

                    var parser = SSEParser()
                    var lineBuffer: [UInt8] = []
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            let line = String(bytes: lineBuffer, encoding: .utf8) ?? ""
                            lineBuffer.removeAll(keepingCapacity: true)
                            for frame in parser.feedLines([line]) {
                                try Self.handleNarrativeFrame(frame: frame, continuation: continuation)
                            }
                        } else {
                            lineBuffer.append(byte)
                        }
                    }
                    if !lineBuffer.isEmpty {
                        let line = String(bytes: lineBuffer, encoding: .utf8) ?? ""
                        for frame in parser.feedLines([line]) {
                            try Self.handleNarrativeFrame(frame: frame, continuation: continuation)
                        }
                    }
                    for frame in parser.feedLines([""]) {
                        try Self.handleNarrativeFrame(frame: frame, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func handleNarrativeFrame(
        frame: SSEFrame,
        continuation: AsyncThrowingStream<NarrativeStreamEvent, Error>.Continuation
    ) throws {
        guard let payload = frame.data.data(using: .utf8) else { return }
        switch frame.event {
        case "delta":
            struct DeltaPayload: Codable { let json: String }
            if let d = try? JSONDecoder().decode(DeltaPayload.self, from: payload) {
                continuation.yield(.jsonDelta(d.json))
            }
        case "done":
            struct DonePayload: Codable {
                let turnId: String
                let narrative: SummarizeTurnResponse.NarrativePayload
                let model: String
                let cacheHit: Bool
                enum CodingKeys: String, CodingKey {
                    case turnId = "turn_id"
                    case narrative, model
                    case cacheHit = "cache_hit"
                }
            }
            if let d = try? JSONDecoder().decode(DonePayload.self, from: payload) {
                continuation.yield(.done(narrative: d.narrative, model: d.model, cacheHit: d.cacheHit))
            }
        case "error":
            let parsed = try? JSONDecoder().decode(SummarizeTurnError.self, from: payload)
            throw ReflectionAPIError.http(status: 502, body: parsed)
        default:
            break
        }
    }

    func summarizeSession(_ request: SummarizeSessionRequest) async throws -> SummarizeSessionResponse {
        let token = try await authTokenProvider()

        var urlRequest = URLRequest(url: Self.sessionEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ReflectionAPIError.malformedResponse }

        if http.statusCode == 200 {
            do {
                return try JSONDecoder().decode(SummarizeSessionResponse.self, from: data)
            } catch { throw ReflectionAPIError.malformedResponse }
        }

        let parsed = try? JSONDecoder().decode(SummarizeTurnError.self, from: data)
        throw ReflectionAPIError.http(status: http.statusCode, body: parsed)
    }

    func summarizeSessionStream(_ request: SummarizeSessionRequest) -> AsyncThrowingStream<SessionSummaryStreamEvent, Error> {
        let capturedSession = session
        let capturedAuthTokenProvider = authTokenProvider
        var streamURL = URLComponents(url: Self.sessionEndpoint, resolvingAgainstBaseURL: false)!
        streamURL.queryItems = [URLQueryItem(name: "stream", value: "true")]
        let url = streamURL.url!

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let token = try await capturedAuthTokenProvider()

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, response) = try await capturedSession.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw ReflectionAPIError.malformedResponse
                    }

                    if http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        let parsed = try? JSONDecoder().decode(SummarizeTurnError.self, from: data)
                        throw ReflectionAPIError.http(status: http.statusCode, body: parsed)
                    }

                    continuation.yield(.started)

                    var parser = SSEParser()
                    var lineBuffer: [UInt8] = []
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            let line = String(bytes: lineBuffer, encoding: .utf8) ?? ""
                            lineBuffer.removeAll(keepingCapacity: true)
                            for frame in parser.feedLines([line]) {
                                try Self.handleSessionFrame(frame: frame, continuation: continuation)
                            }
                        } else {
                            lineBuffer.append(byte)
                        }
                    }
                    if !lineBuffer.isEmpty {
                        let line = String(bytes: lineBuffer, encoding: .utf8) ?? ""
                        for frame in parser.feedLines([line]) {
                            try Self.handleSessionFrame(frame: frame, continuation: continuation)
                        }
                    }
                    for frame in parser.feedLines([""]) {
                        try Self.handleSessionFrame(frame: frame, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func handleSessionFrame(
        frame: SSEFrame,
        continuation: AsyncThrowingStream<SessionSummaryStreamEvent, Error>.Continuation
    ) throws {
        guard let payload = frame.data.data(using: .utf8) else { return }
        switch frame.event {
        case "delta":
            struct DeltaPayload: Codable { let json: String }
            if let d = try? JSONDecoder().decode(DeltaPayload.self, from: payload) {
                continuation.yield(.jsonDelta(d.json))
            }
        case "done":
            struct DonePayload: Codable {
                let sessionId: String
                let summary: SummarizeSessionResponse.SummaryPayload
                let model: String
                enum CodingKeys: String, CodingKey {
                    case sessionId = "session_id"
                    case summary, model
                }
            }
            if let d = try? JSONDecoder().decode(DonePayload.self, from: payload) {
                continuation.yield(.done(summary: d.summary, model: d.model, briefUpdate: d.summary.briefUpdate, projectOverview: d.summary.projectOverview))
            }
        case "error":
            let parsed = try? JSONDecoder().decode(SummarizeTurnError.self, from: payload)
            throw ReflectionAPIError.http(status: 502, body: parsed)
        default:
            break
        }
    }

    func chatSessionStream(_ request: ChatSessionRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        // Capture actor-isolated values before entering the Task, so the Task
        // can run detached (off MainActor) and freely use URLSession.bytes without
        // risking a deadlock on the main actor while waiting for streaming data.
        let capturedSession = session
        let capturedAuthTokenProvider = authTokenProvider
        let chatEndpoint = Self.chatEndpoint

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let token = try await capturedAuthTokenProvider()

                    var urlRequest = URLRequest(url: chatEndpoint)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, response) = try await capturedSession.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw ReflectionAPIError.malformedResponse
                    }

                    if http.statusCode != 200 {
                        // Non-streaming error body. Read fully then throw.
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                        }
                        let parsed = try? JSONDecoder().decode(SummarizeTurnError.self, from: data)
                        throw ReflectionAPIError.http(status: http.statusCode, body: parsed)
                    }

                    var parser = SSEParser()
                    var lineBuffer: [UInt8] = []
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            let line = String(bytes: lineBuffer, encoding: .utf8) ?? ""
                            lineBuffer.removeAll(keepingCapacity: true)
                            for frame in parser.feedLines([line]) {
                                try Self.handle(frame: frame, continuation: continuation)
                            }
                        } else {
                            lineBuffer.append(byte)
                        }
                    }
                    // Flush leftover bytes (no trailing newline).
                    if !lineBuffer.isEmpty {
                        let line = String(bytes: lineBuffer, encoding: .utf8) ?? ""
                        for frame in parser.feedLines([line]) {
                            try Self.handle(frame: frame, continuation: continuation)
                        }
                    }
                    // Flush any final frame (server should always end with blank line, but be safe).
                    for frame in parser.feedLines([""]) {
                        try Self.handle(frame: frame, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func handle(
        frame: SSEFrame,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) throws {
        guard let payload = frame.data.data(using: .utf8) else { return }
        switch frame.event {
        case "delta":
            struct DeltaPayload: Codable { let text: String }
            if let d = try? JSONDecoder().decode(DeltaPayload.self, from: payload) {
                continuation.yield(.delta(d.text))
            }
        case "done":
            struct DonePayload: Codable {
                let model: String
                let cacheHit: Bool
                enum CodingKeys: String, CodingKey { case model; case cacheHit = "cache_hit" }
            }
            if let d = try? JSONDecoder().decode(DonePayload.self, from: payload) {
                continuation.yield(.done(model: d.model, cacheHit: d.cacheHit))
            }
        case "error":
            let parsed = try? JSONDecoder().decode(SummarizeTurnError.self, from: payload)
            throw ReflectionAPIError.http(status: 502, body: parsed)
        default:
            break
        }
    }

    // MARK: - Guidance (non-streaming)

    func fetchGuidance(_ request: GenerateGuidanceRequest) async throws -> GenerateGuidanceResponse {
        let token = try await authTokenProvider()

        var urlRequest = URLRequest(url: Self.guidanceEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ReflectionAPIError.malformedResponse
        }

        if http.statusCode == 200 {
            do {
                return try JSONDecoder().decode(GenerateGuidanceResponse.self, from: data)
            } catch {
                throw ReflectionAPIError.malformedResponse
            }
        }

        let parsed = try? JSONDecoder().decode(SummarizeTurnError.self, from: data)
        throw ReflectionAPIError.http(status: http.statusCode, body: parsed)
    }

    // MARK: - Plan (non-streaming)

    func fetchPlan(_ request: GeneratePlanRequest) async throws -> GeneratePlanResponse {
        let token = try await authTokenProvider()

        var urlRequest = URLRequest(url: Self.planEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ReflectionAPIError.malformedResponse
        }

        if http.statusCode == 200 {
            do {
                return try JSONDecoder().decode(GeneratePlanResponse.self, from: data)
            } catch {
                throw ReflectionAPIError.malformedResponse
            }
        }

        let parsed = try? JSONDecoder().decode(SummarizeTurnError.self, from: data)
        throw ReflectionAPIError.http(status: http.statusCode, body: parsed)
    }

    // MARK: - Distill Reference (non-streaming)

    func fetchReferenceDistillation(_ request: DistillReferenceRequest) async throws -> DistillReferenceResponse {
        let token = try await authTokenProvider()

        var urlRequest = URLRequest(url: Self.distillEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ReflectionAPIError.malformedResponse
        }

        if http.statusCode == 200 {
            do {
                return try JSONDecoder().decode(DistillReferenceResponse.self, from: data)
            } catch {
                throw ReflectionAPIError.malformedResponse
            }
        }

        let parsed = try? JSONDecoder().decode(SummarizeTurnError.self, from: data)
        throw ReflectionAPIError.http(status: http.statusCode, body: parsed)
    }

    // MARK: - Synthesize Brief (non-streaming)

    func synthesizeBrief(_ request: SynthesizeBriefRequest) async throws -> SynthesizeBriefResponse {
        let token = try await authTokenProvider()

        var urlRequest = URLRequest(url: Self.synthesizeBriefEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ReflectionAPIError.malformedResponse
        }

        if http.statusCode == 200 {
            do {
                return try JSONDecoder().decode(SynthesizeBriefResponse.self, from: data)
            } catch {
                throw ReflectionAPIError.malformedResponse
            }
        }

        let parsed = try? JSONDecoder().decode(SummarizeTurnError.self, from: data)
        throw ReflectionAPIError.http(status: http.statusCode, body: parsed)
    }

    // MARK: - Dictionary (non-streaming)

    func fetchDictionary(_ request: GenerateDictionaryRequest) async throws -> GenerateDictionaryResponse {
        let token = try await authTokenProvider()

        var urlRequest = URLRequest(url: Self.dictionaryEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ReflectionAPIError.malformedResponse
        }

        if http.statusCode == 200 {
            do {
                return try JSONDecoder().decode(GenerateDictionaryResponse.self, from: data)
            } catch {
                throw ReflectionAPIError.malformedResponse
            }
        }

        let parsed = try? JSONDecoder().decode(SummarizeTurnError.self, from: data)
        throw ReflectionAPIError.http(status: http.statusCode, body: parsed)
    }

    // MARK: - Enrich Brief (non-streaming)

    func enrichBrief(_ brief: CompanyBrief) async throws -> CompanyBrief {
        let token = try await authTokenProvider()
        var urlRequest = URLRequest(url: Self.enrichBriefEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(EnrichBriefRequest(brief: brief))

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ReflectionAPIError.malformedResponse }
        if http.statusCode == 200 {
            do { return try JSONDecoder().decode(EnrichBriefResponse.self, from: data).brief }
            catch { throw ReflectionAPIError.malformedResponse }
        }
        throw ReflectionAPIError.http(status: http.statusCode, body: nil)
    }

    // MARK: - Scaffold Roadmap

    func scaffoldRoadmap(brief: CompanyBrief, stage: ProjectStage, departments: [RoadmapDeptInput]) async throws -> [RoadmapTask] {
        let token = try await authTokenProvider()
        var urlRequest = URLRequest(url: Self.scaffoldRoadmapEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(
            ScaffoldRoadmapRequest(brief: brief, stage: stage.rawValue, departments: departments))

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ReflectionAPIError.malformedResponse }
        guard http.statusCode == 200 else { throw ReflectionAPIError.http(status: http.statusCode, body: nil) }
        let decoded: ScaffoldRoadmapResponse
        do { decoded = try JSONDecoder().decode(ScaffoldRoadmapResponse.self, from: data) }
        catch { throw ReflectionAPIError.malformedResponse }

        var out: [RoadmapTask] = []
        var perDeptCount: [String: Int] = [:]
        for dept in decoded.departments {
            guard let pillar = HealthPillar(rawValue: dept.key) else { continue }
            for t in dept.tasks {
                let idx = perDeptCount[dept.key, default: 0]
                out.append(RoadmapTask(
                    id: "\(dept.key)-\(idx)", deptKey: pillar, title: t.title, detail: t.detail,
                    who: TaskWho(rawValue: t.who) ?? .draft, kind: t.kind, done: false))
                perDeptCount[dept.key] = idx + 1
            }
        }
        return out
    }
}
