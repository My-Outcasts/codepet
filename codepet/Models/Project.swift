import Foundation

/// A detected project, identified by its root directory path.
/// Projects are auto-detected from the `cwd` field in JSONL events.
struct Project: Identifiable, Hashable, Codable {
    /// Unique identifier — the normalized absolute path of the project root.
    let id: String              // e.g. "/Users/mona/Projects/codepet"

    /// Human-readable display name derived from the folder name.
    var displayName: String     // e.g. "codepet"

    /// Optional user-provided brief describing the project.
    var brief: String

    /// User-set lifecycle stage. `nil` = let the health engine infer it from
    /// signals (`ProjectHealthEngine.inferStage`). Set explicitly when the user
    /// picks a stage in the Project Health folder header.
    var stage: ProjectStage? = nil

    /// IDs of health rules the user has manually confirmed ("Mark done").
    /// Used for self-attested business/growth checks that leave no detectable
    /// trace in the project's files. An attested rule passes regardless of
    /// auto-detection. Defaults empty so projects persisted before this field
    /// existed decode cleanly.
    var attestations: Set<String> = []

    /// When this project was first seen.
    let firstSeenAt: Date

    /// Last time an event from this project was observed.
    var lastSeenAt: Date

    /// Derives a display name from a path by taking the last path component.
    static func nameFromPath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        return name.isEmpty ? path : name
    }
}
