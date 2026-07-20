// codepet/Views/Tips/RoadmapSectionView.swift
import SwiftUI
import Combine

/// Drives the roadmap section: the department inputs, the generate call, and the
/// busy flag. Kept separate from the View so it is unit-testable.
@MainActor
final class RoadmapSectionModel: ObservableObject {
    @Published var isGenerating = false

    /// The 4 native departments as scaffold inputs (english names + short expertise).
    static func departmentsInput() -> [RoadmapDeptInput] {
        HealthPillar.allCases.map { p in
            RoadmapDeptInput(key: p.rawValue, name: p.label.en, expertise: Self.expertise(p))
        }
    }

    private static func expertise(_ p: HealthPillar) -> String {
        switch p {
        case .engineering: return "Shipping the product: architecture, tests, CI/CD, reliability."
        case .business:    return "Model, pricing, legal basics, and validating demand."
        case .marketing:   return "Positioning, launch, audience, and content."
        case .growth:      return "Retention, activation, analytics, and scaling users."
        }
    }

    /// Generate + persist the roadmap. Fail-open: on error, leaves existing tasks intact.
    func generate(projectId: String, brief: CompanyBrief, stage: ProjectStage,
                  store: ProjectStore, api: ReflectionAPIClientProtocol) async {
        isGenerating = true
        defer { isGenerating = false }
        guard let tasks = try? await api.scaffoldRoadmap(
            brief: brief, stage: stage, departments: Self.departmentsInput()), !tasks.isEmpty else { return }
        store.setRoadmapTasks(projectId: projectId, tasks: tasks)
    }
}

/// Roadmap section: a next-step beacon, a "To build" list per department, and a
/// Generate/Re-plan action. Rendered inside ProjectFolderContentView beside the checks.
struct RoadmapSectionView: View {
    let projectPath: String
    let stage: ProjectStage
    let brief: CompanyBrief
    @EnvironmentObject var projectStore: ProjectStore
    @StateObject private var model = RoadmapSectionModel()
    private let api: ReflectionAPIClientProtocol = ReflectionAPIClient()

    private var tasks: [RoadmapTask] { projectStore.roadmapTasks(for: projectPath) }
    private var next: RoadmapNextStep? { RoadmapEngine.nextStep(tasks, stage: stage) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let next = next {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next step").font(.caption).foregroundColor(.secondary)
                    Text(next.taskTitle).font(.headline)
                    Text(next.why).font(.caption).foregroundColor(.secondary)
                }
            }
            ForEach(HealthPillar.allCases, id: \.self) { pillar in
                let group = tasks.filter { $0.deptKey == pillar }
                if !group.isEmpty {
                    Text("To build — \(pillar.label.en)").font(.subheadline.weight(.semibold))
                    ForEach(group) { task in
                        Button { projectStore.toggleRoadmapTask(projectId: projectPath, taskId: task.id) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text(task.title).strikethrough(task.done)
                                    Text(task.detail).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button {
                Task { await model.generate(projectId: projectPath, brief: brief, stage: stage, store: projectStore, api: api) }
            } label: {
                Text(model.isGenerating ? "Planning…" : (tasks.isEmpty ? "Generate roadmap" : "Re-plan for my stage"))
            }
            .buttonStyle(.plain)
            .disabled(model.isGenerating)
        }
    }
}
