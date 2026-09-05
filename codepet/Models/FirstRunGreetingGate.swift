// codepet/Models/FirstRunGreetingGate.swift
import Foundation

/// Whether to greet the founder, as one pure decision.
///
/// **Why this type exists.** `FirstRunGreetingBuilder` and `CompanyStore.seedFirstRunGreeting`
/// were both correct and both dead: the greeting was reachable only from the first-run enrich
/// interview's completion, and nothing in the app starts that interview (see
/// `startEnrichInterviewIfNeeded`'s own comment). A new founder got the hero and a beacon card,
/// and the message that names their first move never ran.
///
/// Pulled out as a static rather than written inline in `hydrate` for the same reason
/// `DraftPayloadPreview.hasStructuredPreview` is: the decision is where a bug here would live,
/// and a condition inside an async store method is only testable by driving the whole store.
enum FirstRunGreetingGate {

    /// - `hasBeenGreeted`: `company.greetedAt != nil` — account-scoped and persisted.
    /// - `transcriptIsEmpty`: never greet into a conversation already in progress.
    /// - `hasTasks`: the greeting's value is naming the first move. With no roadmap,
    ///   `RoadmapEngine.nextStep` is nil and the builder falls back to "Take a look around…",
    ///   which is not worth spending a once-per-account message on. Waiting costs nothing —
    ///   the next hydrate has a task to name.
    static func shouldGreet(hasBeenGreeted: Bool,
                            transcriptIsEmpty: Bool,
                            hasTasks: Bool) -> Bool {
        !hasBeenGreeted && transcriptIsEmpty && hasTasks
    }
}
