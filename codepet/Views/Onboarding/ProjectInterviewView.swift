// codepet/Views/Onboarding/ProjectInterviewView.swift
import SwiftUI

/// Per-project founder interview. Skippable and non-blocking; on finish it
/// enriches + persists via the model. Presented as a sheet (see Task 8).
struct ProjectInterviewView: View {
    let projectId: String
    let onDone: () -> Void
    @EnvironmentObject var projectStore: ProjectStore
    @StateObject private var model = ProjectInterviewModel()
    @State private var step = 0
    private let api: ReflectionAPIClientProtocol = ReflectionAPIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case 0: field("First — what should I call you?", text: $model.founderName, placeholder: "e.g. Mona")
            case 1: field("Which best describes you?", text: $model.role, placeholder: "e.g. Founder")
            case 2: field("What's this project called?", text: $model.projectName, placeholder: "e.g. Codepet")
            case 3: field("In one line, what is it?", text: $model.oneLiner, placeholder: "e.g. a recap tool for founders")
            case 4: field("Who is it for?", text: $model.audience, placeholder: "e.g. solo founders shipping with AI")
            default:
                Text("What stage is it at?").font(.headline)
                Picker("Stage", selection: $model.stageIndex) {
                    ForEach(Array(ProjectInterviewModel.stages.enumerated()), id: \.offset) { i, s in Text(s).tag(i) }
                }.pickerStyle(.segmented)
            }
            HStack {
                Button("Skip") { onDone() }
                Spacer()
                if step < 5 {
                    Button("Next") { step += 1 }.disabled(false)
                } else {
                    Button(model.isSubmitting ? "Saving…" : "Finish") {
                        Task { _ = await model.submit(projectId: projectId, store: projectStore, api: api); onDone() }
                    }.disabled(model.isSubmitting)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }
}
