import Foundation

/// Turns the banked `AgencySignal` stream into visible improvement. Pure and
/// deterministic — no I/O and no clock except the injected `now` — so it is
/// fully unit-testable, mirroring `TermDetector`.
///
/// A dimension D is a RISING trajectory when ALL of these hold:
///   - it was flagged `growth` ≥ `minEarlierGrowth` times in the EARLIER window
///     (a real, repeated edge — not a one-off);
///   - it is flagged `strength` ≥ `minRecentStrength` times in the RECENT window
///     (positive confirmation it is now done well — not mere silence);
///   - it has NO `growth` flag in the recent window (the edge is closed);
///   - its signals span ≥ `minSpanDays` (a trajectory, not one good day);
///   - the whole log covers ≥ `minSessions` distinct sessions (not noise).
///
/// Requiring a recent *strength* (not just the disappearance of growth) is the
/// honesty guarantee: absence of a growth edge could merely mean the user did
/// less risky work; an affirmative strength cannot be faked that way.
struct TrajectoryDetector {

    struct Config {
        /// Signals at or after `now - recentWindow` are "recent"; older ones are
        /// "earlier".
        var recentWindow: TimeInterval = 14 * 86_400
        var minEarlierGrowth = 2
        var minRecentStrength = 1
        var minSpanDays = 10
        var minSessions = 6

        init() {}
    }

    /// All rising trajectories, strongest first — for the Profile "How you've
    /// grown" list. Deterministic ordering.
    static func detectAll(
        signals: [AgencySignal],
        now: Date = Date(),
        config: Config = Config()
    ) -> [Trajectory] {
        // Enough total history to trust any signal at all.
        let distinctSessions = Set(signals.map(\.sessionId))
        guard distinctSessions.count >= config.minSessions else { return [] }

        let recentCutoff = now.addingTimeInterval(-config.recentWindow)
        let growth = AgencySignal.Valence.growth.rawValue
        let strength = AgencySignal.Valence.strength.rawValue

        // Group by normalized dimension so casing never splits a pattern.
        var byDimension: [String: [AgencySignal]] = [:]
        for s in signals {
            byDimension[s.signal.lowercased(), default: []].append(s)
        }

        var rising: [Trajectory] = []
        for (dimension, group) in byDimension {
            let earlierGrowth = group.filter { $0.createdAt < recentCutoff && $0.valence == growth }.count
            let recentStrength = group.filter { $0.createdAt >= recentCutoff && $0.valence == strength }.count
            let recentGrowth = group.filter { $0.createdAt >= recentCutoff && $0.valence == growth }.count

            guard earlierGrowth >= config.minEarlierGrowth,
                  recentStrength >= config.minRecentStrength,
                  recentGrowth == 0
            else { continue }

            let dates = group.map(\.createdAt)
            guard let first = dates.min(), let last = dates.max() else { continue }
            guard Int(last.timeIntervalSince(first) / 86_400) >= config.minSpanDays else { continue }

            rising.append(Trajectory(
                signal: dimension,
                earlierGrowthCount: earlierGrowth,
                recentStrengthCount: recentStrength,
                firstSeen: first,
                lastSeen: last
            ))
        }

        // Strongest first: by (Eg + Rs), then Eg, then most-recent lastSeen, then
        // dimension name — fully deterministic so tests and UI never reorder.
        return rising.sorted { a, b in
            let sa = a.earlierGrowthCount + a.recentStrengthCount
            let sb = b.earlierGrowthCount + b.recentStrengthCount
            if sa != sb { return sa > sb }
            if a.earlierGrowthCount != b.earlierGrowthCount { return a.earlierGrowthCount > b.earlierGrowthCount }
            if a.lastSeen != b.lastSeen { return a.lastSeen > b.lastSeen }
            return a.signal < b.signal
        }
    }

    /// The single strongest rising trajectory — for the one-time milestone
    /// moment — or nil if none qualifies.
    static func strongest(
        signals: [AgencySignal],
        now: Date = Date(),
        config: Config = Config()
    ) -> Trajectory? {
        detectAll(signals: signals, now: now, config: config).first
    }
}
