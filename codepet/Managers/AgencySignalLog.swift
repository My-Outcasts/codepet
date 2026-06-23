import Foundation
import Combine

/// The Learner Model's data-collection layer.
///
/// An append-only, locally-persisted log of every `AgencySignal` the session
/// summarizer produces. Today it feeds exactly one thing — the single "growth
/// edge" sentence under the Reflection hero. But its real job is to *bank clean,
/// labeled signal over time* so that when the two-axis Learner Model is built,
/// it has months of real history to aggregate instead of a cold start.
///
/// Deliberately client-side for the beta (UserDefaults, `cp_agency_signals`): no
/// new production Firestore schema is committed yet. When the Learner Model
/// lands, this log is the clean event stream it reads — and can be synced up via
/// the existing CloudSync path.
@MainActor
final class AgencySignalLog: ObservableObject {

    static let shared = AgencySignalLog()

    /// Newest-last. Capped so the log can't grow without bound on-device.
    @Published private(set) var signals: [AgencySignal] = []

    /// Trajectory ids already shown as a one-time milestone moment. A surfaced
    /// trajectory never interrupts again — it lives on in Profile thereafter.
    @Published private(set) var surfacedMilestones: Set<String> = []

    private let defaults = UserDefaults.standard
    private let key = "cp_agency_signals"
    private let surfacedKey = "cp_trajectory_seen"
    private let maxEntries = 500

    init() { load(); loadSurfaced() }

    // MARK: - Ingest

    /// Record the signals from one freshly-summarized session. Idempotent per
    /// (session, signal, valence): re-summarizing a session replaces that
    /// session's prior signals rather than duplicating them.
    func record(_ incoming: [AgencySignal]) {
        guard !incoming.isEmpty else { return }
        let touchedSessions = Set(incoming.map(\.sessionId))
        var next = signals.filter { !touchedSessions.contains($0.sessionId) }
        next.append(contentsOf: incoming)
        if next.count > maxEntries { next.removeFirst(next.count - maxEntries) }
        signals = next
        save()
    }

    // MARK: - Read helpers (what the Learner Model will lean on)

    /// The most recent growth-edge observation to surface in the UI, if any.
    func latestGrowthEdge(forSession sessionId: String) -> AgencySignal? {
        signals.last { $0.sessionId == sessionId && $0.isGrowth }
    }

    /// All signals for one process pattern (e.g. how often "verification" has
    /// come up) — the kind of aggregate the Learner Model is built on.
    func signals(forPattern signal: AgencySignal.Signal) -> [AgencySignal] {
        signals.filter { $0.signal == signal.rawValue }
    }

    // MARK: - Milestone moment (shown once)

    /// The strongest rising trajectory that has NOT yet been surfaced as a
    /// one-time milestone, or nil. The Reflection milestone reads this.
    func pendingMilestone(now: Date = Date()) -> Trajectory? {
        guard let strongest = TrajectoryDetector.strongest(signals: signals, now: now) else { return nil }
        return surfacedMilestones.contains(strongest.id) ? nil : strongest
    }

    /// Record that a milestone has been shown once. After this it never
    /// interrupts again (it remains visible in Profile → "How you've grown").
    func markMilestoneSurfaced(_ trajectory: Trajectory) {
        guard !surfacedMilestones.contains(trajectory.id) else { return }
        surfacedMilestones.insert(trajectory.id)
        saveSurfaced()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(signals) {
            defaults.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AgencySignal].self, from: data)
        else { return }
        signals = decoded
    }

    private func saveSurfaced() {
        defaults.set(Array(surfacedMilestones), forKey: surfacedKey)
    }

    private func loadSurfaced() {
        if let arr = defaults.stringArray(forKey: surfacedKey) {
            surfacedMilestones = Set(arr)
        }
    }

    func resetAll() {
        signals = []
        surfacedMilestones = []
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: surfacedKey)
    }
}
