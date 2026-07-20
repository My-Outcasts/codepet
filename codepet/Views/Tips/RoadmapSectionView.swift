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
/// Generate/Re-plan action. Rendered inside ProjectFolderContentView beside the
/// checks. Styled with the app's web-matched design system (`CodepetTheme` +
/// `pixelBox` tinted cards + `.pixelSystem` type), localized VI/EN.
struct RoadmapSectionView: View {
    let projectPath: String
    let stage: ProjectStage
    let brief: CompanyBrief
    @EnvironmentObject var projectStore: ProjectStore
    @Environment(\.uiLanguage) private var uiLanguage
    @StateObject private var model = RoadmapSectionModel()
    private let api: ReflectionAPIClientProtocol = ReflectionAPIClient()

    private var tasks: [RoadmapTask] { projectStore.roadmapTasks(for: projectPath) }
    private var next: RoadmapNextStep? { RoadmapEngine.nextStep(tasks, stage: stage) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(uiLanguage == .vi ? "Lộ trình" : "Roadmap")

            if let next = next {
                nextStepBeacon(next)
            }

            ForEach(HealthPillar.allCases, id: \.self) { pillar in
                let group = tasks.filter { $0.deptKey == pillar }
                if !group.isEmpty {
                    Text((uiLanguage == .vi ? "Cần làm — " : "To build — ") + pillar.label(uiLanguage))
                        .font(.pixelSystem(size: 11, weight: .bold))
                        .foregroundColor(CodepetTheme.mutedText)
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .padding(.top, 6)
                    ForEach(group) { task in
                        taskRow(task, accent: color(for: pillar))
                    }
                }
            }

            generateButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.pixelSystem(size: 13, weight: .bold))
            .foregroundColor(CodepetTheme.primaryText.opacity(0.55))
            .tracking(0.8)
            .textCase(.uppercase)
            .padding(.top, 16)
            .padding(.bottom, 2)
    }

    private func nextStepBeacon(_ next: RoadmapNextStep) -> some View {
        let accent = color(for: next.deptKey)
        return VStack(alignment: .leading, spacing: 4) {
            Text(uiLanguage == .vi ? "BƯỚC TIẾP THEO" : "NEXT STEP")
                .font(.pixelSystem(size: 9, weight: .bold))
                .foregroundColor(accent)
                .tracking(0.8)
            Text(next.taskTitle)
                .font(.pixelSystem(size: 14, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(next.why)
                .font(.pixelSystem(size: 11))
                .foregroundColor(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .pixelBox(fill: accent.opacity(0.08), borderColor: accent.opacity(0.28),
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
    }

    private func taskRow(_ task: RoadmapTask, accent: Color) -> some View {
        Button {
            projectStore.toggleRoadmapTask(projectId: projectPath, taskId: task.id)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: task.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundColor(task.done ? accent : CodepetTheme.mutedText)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                        .strikethrough(task.done)
                    Text(task.detail)
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pixelBox(fill: accent.opacity(0.06), borderColor: accent.opacity(0.20),
                      shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
        }
        .buttonStyle(.plain)
        .opacity(task.done ? 0.65 : 1.0)
    }

    private var generateButton: some View {
        Button {
            Task { await model.generate(projectId: projectPath, brief: brief, stage: stage, store: projectStore, api: api) }
        } label: {
            Text(generateLabel)
                .font(.pixelSystem(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(CodepetTheme.accentPurple))
                .opacity(model.isGenerating ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(model.isGenerating)
        .padding(.top, 4)
    }

    private var generateLabel: String {
        if model.isGenerating { return uiLanguage == .vi ? "Đang lập kế hoạch…" : "Planning…" }
        if tasks.isEmpty { return uiLanguage == .vi ? "Tạo lộ trình" : "Generate roadmap" }
        return uiLanguage == .vi ? "Lập lại theo giai đoạn" : "Re-plan for my stage"
    }

    /// Per-department accent, matching the web's per-department tinting.
    private func color(for pillar: HealthPillar) -> Color {
        switch pillar {
        case .engineering: return CodepetTheme.accentPurple
        case .business:    return CodepetTheme.accentBlue
        case .marketing:   return CodepetTheme.accentPink
        case .growth:      return CodepetTheme.accentTeal
        }
    }
}
