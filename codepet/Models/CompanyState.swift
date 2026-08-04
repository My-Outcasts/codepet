// codepet/Models/CompanyState.swift
import Foundation

/// Vestigial department skeleton (key + name) from an earlier phase — the real
/// department model is `Department` in Department.swift. Kept only because the
/// `CompanyState.departments` field (always empty, never read) is typed on it;
/// renamed to avoid colliding with the real `Department`.
struct DeptRef: Codable, Hashable, Identifiable {
    let key: String
    var name: String
    var id: String { key }
}

/// The single company's in-memory state (companies/{uid}). `tasks` is the
/// roadmap and `library` is the delivered work — both loaded from the doc.
/// Departments is typed but empty until a later phase populates it.
struct CompanyState: Codable, Hashable {
    var brief: CompanyBrief
    var departments: [DeptRef]
    var library: [Deliverable]
    var stage: ProjectStage
    var companionId: String
    var onboardedAt: Date?
    /// When this account first saw the Overview briefing. Account-scoped (not per-device) so
    /// the one-time intro doesn't reappear on another machine. Mirrors the web's
    /// `companies/{uid}.introSeenAt`.
    var introSeenAt: Date?
    var tasks: [RoadmapTask]
    var enabledTools: Set<String>
    var decisions: [DecisionEntry]
    /// Settings the founder chose in the settings modal. Defaulted, because every company
    /// doc written before this field existed decodes without it.
    var founderPrefs: FounderPrefs

    /// Explicit memberwise init so `tasks`/`enabledTools`/`decisions`/`founderPrefs` can
    /// default — existing call sites that predate the roadmap/environment/settings phases
    /// omit them and keep compiling.
    init(brief: CompanyBrief, departments: [DeptRef], library: [Deliverable],
         stage: ProjectStage, companionId: String, onboardedAt: Date? = nil,
         introSeenAt: Date? = nil,
         tasks: [RoadmapTask] = [], enabledTools: Set<String> = Toolkit.defaultEnabledIds,
         decisions: [DecisionEntry] = [],
         founderPrefs: FounderPrefs = .init()) {
        self.brief = brief
        self.departments = departments
        self.library = library
        self.stage = stage
        self.companionId = companionId
        self.onboardedAt = onboardedAt
        self.introSeenAt = introSeenAt
        self.tasks = tasks
        self.enabledTools = enabledTools
        self.decisions = decisions
        self.founderPrefs = founderPrefs
    }

    /// Hand-written so a company document that predates a field still decodes: Swift's
    /// synthesised `Decodable` calls `decode(forKey:)`, which throws `keyNotFound` rather
    /// than falling back to the property's declared default. `founderPrefs` is the field
    /// that forced this — every doc in Firestore was written before it existed — but every
    /// key gets the same treatment, and the same default as the memberwise init above, so
    /// the next added field doesn't have to relearn the lesson. Encoding stays synthesised.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brief = try c.decodeIfPresent(CompanyBrief.self, forKey: .brief) ?? CompanyBrief()
        departments = try c.decodeIfPresent([DeptRef].self, forKey: .departments) ?? []
        library = try c.decodeIfPresent([Deliverable].self, forKey: .library) ?? []
        stage = try c.decodeIfPresent(ProjectStage.self, forKey: .stage) ?? .idea
        companionId = try c.decodeIfPresent(String.self, forKey: .companionId) ?? "byte"
        onboardedAt = try c.decodeIfPresent(Date.self, forKey: .onboardedAt)
        introSeenAt = try c.decodeIfPresent(Date.self, forKey: .introSeenAt)
        tasks = try c.decodeIfPresent([RoadmapTask].self, forKey: .tasks) ?? []
        enabledTools = try c.decodeIfPresent(Set<String>.self, forKey: .enabledTools)
            ?? Toolkit.defaultEnabledIds
        decisions = try c.decodeIfPresent([DecisionEntry].self, forKey: .decisions) ?? []
        founderPrefs = try c.decodeIfPresent(FounderPrefs.self, forKey: .founderPrefs) ?? .init()
    }

    static let empty = CompanyState(
        brief: CompanyBrief(), departments: [], library: [], stage: .idea, companionId: "byte", onboardedAt: nil)
}
