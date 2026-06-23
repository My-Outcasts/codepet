import Foundation

/// A detected, evidence-grounded improvement in one process pattern over time —
/// the "agency axis made visible." Produced by `TrajectoryDetector` from the
/// banked `AgencySignal` stream, then rendered as the Reflection milestone
/// moment and the Profile "How you've grown" record.
///
/// Only RISING trajectories exist, by design: a pattern that was a *repeated*
/// growth edge and is *now affirmatively* a strength. Regressions are handled by
/// silence (the trajectory simply stops being produced) — never by a "you got
/// worse" claim.
struct Trajectory: Codable, Hashable, Identifiable {
    /// The process dimension, an `AgencySignal.Signal` raw value (lowercased).
    let signal: String
    /// Times this was flagged as a growth edge in the earlier window (Eg).
    let earlierGrowthCount: Int
    /// Times it was affirmed as a strength in the recent window (Rs).
    let recentStrengthCount: Int
    /// Earliest signal on this dimension (the start of the journey).
    let firstSeen: Date
    /// Latest signal on this dimension (where it stands now).
    let lastSeen: Date

    /// Stable identity, so a surfaced trajectory is never surfaced twice.
    var id: String { "\(signal)__rising" }

    var signalValue: AgencySignal.Signal? { AgencySignal.Signal(rawValue: signal) }

    /// Whole days from the first to the last signal on this dimension.
    var spanDays: Int {
        max(0, Int(lastSeen.timeIntervalSince(firstSeen) / 86_400))
    }
}
