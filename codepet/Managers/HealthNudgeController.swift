import Foundation
import Combine
import os

/// Monitors active coding sessions and triggers health reminders from the pet
/// every ~45 minutes. Each nudge has a unique message so it doesn't feel
/// repetitive. The controller tracks session start via event timestamps and
/// fires nudges at regular intervals.
@MainActor
final class HealthNudgeController: ObservableObject {

    /// The currently active nudge to display (nil = no nudge showing).
    @Published var activeNudge: HealthNudge?

    /// How many nudges have been shown in the current session.
    @Published private(set) var nudgeCount: Int = 0

    private let interval: TimeInterval  // seconds between nudges
    private var timer: Timer?
    private var sessionStartTime: Date?
    private let logger = Logger(subsystem: "app.murror.codepet", category: "HealthNudge")

    init(intervalMinutes: Int = 45) {
        self.interval = TimeInterval(intervalMinutes * 60)
    }

    // MARK: - Session lifecycle

    /// Call when a new coding event is detected to mark session as active.
    func markActive() {
        if sessionStartTime == nil {
            sessionStartTime = Date()
            startTimer()
            logger.info("Health nudge timer started")
        }
    }

    /// Call when the session ends or the app goes to background.
    func reset() {
        timer?.invalidate()
        timer = nil
        sessionStartTime = nil
        nudgeCount = 0
        activeNudge = nil
    }

    /// Dismiss the current nudge.
    func dismiss() {
        withMainActorAnimation {
            activeNudge = nil
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fireNudge()
            }
        }
    }

    private func fireNudge() {
        guard activeNudge == nil else { return } // don't stack nudges
        guard let start = sessionStartTime else { return }

        let elapsed = Int(Date().timeIntervalSince(start) / 60)
        nudgeCount += 1

        let nudge = HealthNudge.pick(
            nudgeIndex: nudgeCount,
            minutesElapsed: elapsed
        )
        logger.info("Firing health nudge #\(self.nudgeCount) at \(elapsed) min")
        activeNudge = nudge
    }

    /// Helper for animated state changes.
    private func withMainActorAnimation(_ body: () -> Void) {
        body()
    }
}

// MARK: - HealthNudge model

struct HealthNudge: Identifiable, Equatable {
    let id = UUID()
    let emoji: String
    let title: String           // short label, e.g. "Time to stretch"
    let message: String         // 1-2 sentences from the pet
    let minutesElapsed: Int     // how long the user has been coding

    /// Pick a nudge based on how many have been shown and elapsed time.
    static func pick(nudgeIndex: Int, minutesElapsed: Int) -> HealthNudge {
        let pool = allNudges
        // Cycle through the pool, varying by index
        let entry = pool[(nudgeIndex - 1) % pool.count]
        return HealthNudge(
            emoji: entry.emoji,
            title: entry.title,
            message: entry.message,
            minutesElapsed: minutesElapsed
        )
    }

    private struct Template {
        let emoji: String
        let title: String
        let message: String
    }

    /// Pool of varied nudge messages. Each feels different so recurring
    /// reminders don't get annoying.
    private static let allNudges: [Template] = [
        Template(
            emoji: "💧",
            title: "Water break?",
            message: "You've been coding for a while now. Your brain works better hydrated — grab a glass of water?"
        ),
        Template(
            emoji: "🚶",
            title: "Quick stretch",
            message: "Your shoulders are probably tighter than you think. Stand up, roll them back a few times. I'll be here when you get back."
        ),
        Template(
            emoji: "👀",
            title: "Rest your eyes",
            message: "Look at something 20 feet away for 20 seconds. Your eyes will thank you — screens are tough on them."
        ),
        Template(
            emoji: "🌬️",
            title: "Deep breath",
            message: "Take three slow, deep breaths. In through the nose, out through the mouth. It resets your focus more than you'd expect."
        ),
        Template(
            emoji: "☕",
            title: "Snack time?",
            message: "When's the last time you ate something? A small snack keeps your energy steady. Coding on empty is no fun."
        ),
        Template(
            emoji: "🪟",
            title: "Look outside",
            message: "Open a window or just look out for a moment. A change of scenery — even for 30 seconds — helps your brain process what you've been building."
        ),
        Template(
            emoji: "🧘",
            title: "Posture check",
            message: "How's your back doing? Sit up straight, uncross your legs, feet flat on the floor. Your future self will appreciate it."
        ),
        Template(
            emoji: "🎵",
            title: "Mental reset",
            message: "You've been heads-down for a while. Put on a favorite song, close your eyes for the chorus. Sometimes the best debugging happens when you're not staring at code."
        ),
    ]
}
