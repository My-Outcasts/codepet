import Foundation
import Combine

/// Owns which project (if any) is currently showing the founder interview.
/// A single, minimal presentation seam: call `request(_:)` from any surface
/// that wants to prompt an interview; ContentView presents the sheet.
@MainActor
final class InterviewCoordinator: ObservableObject {
    @Published var active: Project?

    /// Prompt the interview for a project, but only when it has no founder brief.
    func request(_ project: Project) {
        guard ProjectInterviewModel.shouldPrompt(for: project) else { return }
        active = project
    }
}
