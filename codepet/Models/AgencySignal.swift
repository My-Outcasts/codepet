import Foundation

/// One observation about HOW the user worked with their AI in a session — their
/// *process literacy*, not the code they produced. This is the beta's "cheap
/// thread": `observation` is the single kind sentence shown under the Reflection
/// hero, while `axis` / `signal` / `valence` / `evidence` are the structured
/// training data the future two-axis Learner Model will aggregate.
///
/// The vocabularies are kept as plain strings (not enums) so a new server-side
/// `signal` value never fails to decode an older client — the model stays
/// forward-tolerant. The typed accessors below interpret known values.
struct AgencySignal: Codable, Hashable, Identifiable {
    let id: String              // stable: "<sessionId>__<signal>__<valence>"
    let sessionId: String
    let observation: String     // human-facing growth-edge sentence
    let axis: String            // "agency" | "comprehension"
    let signal: String          // scoping|prompting|verification|direction|iteration|context
    let valence: String         // "growth" | "strength"
    let evidence: String        // grounded one-liner (not shown; for the model)
    let language: String        // "vi" | "en"
    let createdAt: Date

    // MARK: - Typed interpretation (tolerant of unknown future values)

    enum Axis: String { case agency, comprehension }
    enum Signal: String { case scoping, prompting, verification, direction, iteration, context }
    enum Valence: String { case growth, strength }

    var axisValue: Axis? { Axis(rawValue: axis) }
    var signalValue: Signal? { Signal(rawValue: signal) }
    var valenceValue: Valence? { Valence(rawValue: valence) }

    var isGrowth: Bool { valence == Valence.growth.rawValue }
    var isStrength: Bool { valence == Valence.strength.rawValue }
}
