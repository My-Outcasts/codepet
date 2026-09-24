// codepet/Models/TeamBuild.swift
import Foundation

/// One founder request, the whole company, a real project — see
/// docs/superpowers/specs/2026-09-24-team-build-design.md.
struct WorkStep: Codable, Hashable, Identifiable {
    let id: String
    let dept: String
    let title: String
    let instruction: String
    let kind: String
    var dependsOn: [String]

    /// A synthetic roadmap task, so the existing run machinery (`runRequest`, `UpstreamWork.fromDraft`)
    /// can be reused unchanged. Never added to `company.tasks`.
    func asRoadmapTask() -> RoadmapTask {
        RoadmapTask(id: "team-\(id)", title: title, detail: instruction, phase: .build, who: .draft,
                    dependsOn: [], dept: dept)
    }
}

struct WorkPlan: Codable, Hashable {
    var title: String
    var slug: String
    var summary: String
    var projectType: String
    var steps: [WorkStep]

    static let buildStepId = "build"
    var buildStep: WorkStep? { steps.first { $0.id == Self.buildStepId } }
    var departmentSteps: [WorkStep] { steps.filter { $0.id != Self.buildStepId } }
}

enum TeamStepStatus: Codable, Hashable {
    case waiting, running, done, failed(String), blocked, cancelled, interrupted
}

struct TeamStepState: Codable, Hashable {
    let stepId: String
    var status: TeamStepStatus = .waiting
    var startedAt: Date?
    var finishedAt: Date?
    var draft: Deliverable?
}

enum TeamRunPhase: String, Codable, Hashable { case planned, running, assembling, ready, filed, cancelled, failed }

struct TeamRun: Codable, Hashable, Identifiable {
    let id: String
    let request: String
    let createdAt: Date
    var brief: VCBrief?
    var plan: WorkPlan
    var steps: [TeamStepState]
    var projectPath: String?
    var phase: TeamRunPhase

    init(id: String = UUID().uuidString, request: String, createdAt: Date, brief: VCBrief?, plan: WorkPlan) {
        self.id = id; self.request = request; self.createdAt = createdAt; self.brief = brief
        self.plan = plan; self.steps = plan.steps.map { TeamStepState(stepId: $0.id) }
        self.projectPath = nil; self.phase = .planned
    }

    func state(_ stepId: String) -> TeamStepState? { steps.first { $0.stepId == stepId } }
    /// Planned, running, assembling or stalled on a failure — anything the founder can still act on
    /// before approval. Gates "one TeamRun per company".
    var isActive: Bool { [.planned, .running, .assembling, .failed].contains(phase) }
}

enum WorkPlanValidation {
    static let routable: Set<String> = ["eng", "design", "mkt", "sales", "support", "fin", "ops", "legal"]
    static let maxDeptSteps = 6
    static let maxDeps = 3

    /// Swift mirror of `coerceWorkPlan` rules 1, 3, 4, 5. Nil only if the plan has no build step
    /// AND nothing valid — which cannot happen after this runs, so callers may force-unwrap in tests.
    static func validate(_ plan: WorkPlan, roster: Set<String>) -> WorkPlan? {
        let allowed = routable.intersection(roster)
        var buildInstruction = plan.buildStep?.instruction ?? ""
        var accepted: [WorkStep] = []
        var ids = Set<String>()
        for var s in plan.steps {
            if s.id == WorkPlan.buildStepId {
                if buildInstruction.isEmpty { buildInstruction = s.instruction }
                continue
            }
            guard allowed.contains(s.dept), !ids.contains(s.id), accepted.count < maxDeptSteps else { continue }
            var seen = Set<String>()
            s.dependsOn = s.dependsOn.filter { ids.contains($0) && seen.insert($0).inserted }.prefix(maxDeps).map { $0 }
            accepted.append(s); ids.insert(s.id)
        }
        let build = WorkStep(id: WorkPlan.buildStepId, dept: "eng", title: plan.buildStep?.title ?? "Build the project",
                             instruction: buildInstruction, kind: "other", dependsOn: accepted.map(\.id))
        var out = plan
        out.steps = accepted + [build]
        return out
    }
}

enum TeamBuildRoomOutcome: Equatable {
    case brief(VCBrief), requestOnly, clarify, failed

    static func from(phase: VCRunPhase, routingDecision: String?, brief: VCBrief?) -> TeamBuildRoomOutcome {
        switch routingDecision {
        case "single_agent": return .requestOnly
        case "needs_clarification": return .clarify
        default:
            if phase == .finished, let brief { return .brief(brief) }
            return .failed
        }
    }
}
