import SwiftUI

// MARK: - Data Models

enum SystemTrapType: String, CaseIterable {
    case driftToLowPerformance
    case successToSuccessful
    case shiftingBurden

    var name: String {
        switch self {
        case .driftToLowPerformance: return "Drift to Low Performance"
        case .successToSuccessful: return "Success to Successful"
        case .shiftingBurden: return "Shifting the Burden"
        }
    }

    var icon: String {
        switch self {
        case .driftToLowPerformance: return "arrow.down.right"
        case .successToSuccessful: return "arrow.triangle.2.circlepath"
        case .shiftingBurden: return "scalemass"
        }
    }

    var description: String {
        switch self {
        case .driftToLowPerformance:
            return "Your recent scores are trending downward. Small drops feel okay, but they compound over time."
        case .successToSuccessful:
            return "You keep practicing skills you're already good at, while avoiding weaker areas."
        case .shiftingBurden:
            return "You're doing new challenges but skipping reviews. New learning without reinforcement fades quickly."
        }
    }

    var suggestedAction: String {
        switch self {
        case .driftToLowPerformance:
            return "Retry a recent challenge and aim for a higher score."
        case .successToSuccessful:
            return "Try a skill you haven't practiced recently."
        case .shiftingBurden:
            return "Complete your overdue reviews before starting new challenges."
        }
    }
}

struct SystemTrap {
    let type: SystemTrapType
    let severity: Double
    let detectedDate: Date
}

struct FeedbackLoop {
    let name: String
    let description: String
    let strength: Double
    let isPositive: Bool
}

struct FeedbackLoopData {
    let reinforcingLoops: [FeedbackLoop]
    let balancingLoops: [FeedbackLoop]

    var strongestReinforcing: FeedbackLoop? {
        reinforcingLoops.max(by: { $0.strength < $1.strength })
    }
}

// MARK: - Resilience Score

extension AppState {
    var resilienceScore: Int {
        let score = Double(consistencyScore) * 0.4
            + Double(recoverySpeedScore) * 0.3
            + Double(reviewHealthScore) * 0.3
        return Int(score.rounded())
    }

    var resilienceLabel: String {
        switch resilienceScore {
        case 80...100: return "Deep Lake"
        case 60..<80: return "Steady River"
        case 40..<60: return "Mountain Stream"
        default: return "Morning Dew"
        }
    }

    var consistencyScore: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today) else { return 0 }
        let recentDays = dailySnapshots.filter { $0.date >= thirtyDaysAgo }.count
        return min(100, recentDays * 100 / 30)
    }

    var recoverySpeedScore: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today) else { return 0 }
        let activeDates = dailySnapshots
            .filter { $0.date >= thirtyDaysAgo }
            .map { calendar.startOfDay(for: $0.date) }
            .sorted()
        guard activeDates.count >= 2 else {
            return activeDates.isEmpty ? 0 : 50
        }
        var totalGap = 0
        var gapCount = 0
        for i in 1..<activeDates.count {
            let gap = calendar.dateComponents([.day], from: activeDates[i - 1], to: activeDates[i]).day ?? 0
            if gap > 1 {
                totalGap += gap
                gapCount += 1
            }
        }
        if gapCount == 0 { return 100 }
        let avgGap = Double(totalGap) / Double(gapCount)
        return max(0, Int((100.0 - avgGap * 15.0).rounded()))
    }

    var reviewHealthScore: Int {
        let completed = completedLessons
        guard !completed.isEmpty else { return 100 }
        let overdueCount = lessonsReadyForReview.count
        let onTrack = completed.count - overdueCount
        return max(0, min(100, onTrack * 100 / completed.count))
    }
}

// MARK: - Trap Detection

extension AppState {
    var activeTraps: [SystemTrap] {
        var traps: [SystemTrap] = []
        if let trap = detectDriftToLowPerformance() { traps.append(trap) }
        if let trap = detectSuccessToSuccessful() { traps.append(trap) }
        if let trap = detectShiftingBurden() { traps.append(trap) }
        return traps
    }

    private func detectDriftToLowPerformance() -> SystemTrap? {
        let recent = performanceHistory.suffix(5)
        guard recent.count >= 3 else { return nil }
        let scores = recent.map(\.score)
        var declining = true
        for i in 1..<scores.count {
            if scores[i] >= scores[i - 1] { declining = false; break }
        }
        guard declining else { return nil }
        let drop = Double(scores.first! - scores.last!) / 100.0
        return SystemTrap(type: .driftToLowPerformance, severity: min(1.0, drop * 2), detectedDate: Date())
    }

    private func detectSuccessToSuccessful() -> SystemTrap? {
        let allSkillIds = GameData.skillTiers.flatMap { $0.skills.map(\.id) }
        let uncompleted = allSkillIds.filter { !completedLessons.contains($0) }
        guard !uncompleted.isEmpty else { return nil }
        let twoWeeksAgo = Date().addingTimeInterval(-14 * 86400)
        let recentSkillIds = performanceHistory.filter { $0.date >= twoWeeksAgo }.map(\.skillId)
        guard !recentSkillIds.isEmpty else { return nil }
        let practicedTiers = Set(recentSkillIds.compactMap { skillId in
            GameData.skillTiers.first { tier in tier.skills.contains { $0.id == skillId } }?.id
        })
        let tiersWithUncompleted = Set(uncompleted.compactMap { skillId in
            GameData.skillTiers.first { tier in tier.skills.contains { $0.id == skillId } }?.id
        })
        let neglectedTiers = tiersWithUncompleted.subtracting(practicedTiers)
        guard practicedTiers.count <= 2 && !neglectedTiers.isEmpty else { return nil }
        return SystemTrap(type: .successToSuccessful, severity: min(1.0, Double(neglectedTiers.count) / Double(GameData.skillTiers.count)), detectedDate: Date())
    }

    private func detectShiftingBurden() -> SystemTrap? {
        let overdueCount = lessonsReadyForReview.count
        guard overdueCount >= 3 else { return nil }
        let oneWeekAgo = Date().addingTimeInterval(-7 * 86400)
        let recentChallenges = performanceHistory.filter { $0.date >= oneWeekAgo }
        guard !recentChallenges.isEmpty else { return nil }
        return SystemTrap(type: .shiftingBurden, severity: min(1.0, Double(overdueCount) / Double(max(1, completedLessons.count))), detectedDate: Date())
    }
}

// MARK: - Feedback Loop Detection

extension AppState {
    var feedbackLoops: FeedbackLoopData {
        FeedbackLoopData(reinforcingLoops: detectReinforcingLoops(), balancingLoops: detectBalancingLoops())
    }

    private func detectReinforcingLoops() -> [FeedbackLoop] {
        var loops: [FeedbackLoop] = []
        let recentSnapshots = dailySnapshots.suffix(7)
        if recentSnapshots.count >= 2 {
            let first = recentSnapshots.first!.totalXP
            let last = recentSnapshots.last!.totalXP
            let growth = last - first
            if growth > 0 {
                loops.append(FeedbackLoop(name: "Learning Momentum", description: "Skills → XP → Level Up → New Skills", strength: min(1.0, Double(growth) / 300.0), isPositive: true))
            }
        }
        if streak > 3 {
            loops.append(FeedbackLoop(name: "Streak Power", description: "Daily Practice → Streak → Motivation → More Practice", strength: min(1.0, Double(streak) / 14.0), isPositive: true))
        }
        let oneWeekAgo = Date().addingTimeInterval(-7 * 86400)
        let recentLessons = performanceHistory.filter { $0.date >= oneWeekAgo }
        let uniqueSkills = Set(recentLessons.map(\.skillId))
        if uniqueSkills.count >= 2 {
            loops.append(FeedbackLoop(name: "Skill Compound", description: "Multiple Skills → Cross-Pollination → Deeper Understanding", strength: min(1.0, Double(uniqueSkills.count) / 4.0), isPositive: true))
        }
        return loops
    }

    private func detectBalancingLoops() -> [FeedbackLoop] {
        var loops: [FeedbackLoop] = []
        if petEnergy < 40 {
            loops.append(FeedbackLoop(name: "Energy Drain", description: "Low Energy → Low Mood → Less Practice → Lower Energy", strength: Double(40 - petEnergy) / 40.0, isPositive: false))
        }
        let overdueCount = lessonsReadyForReview.count
        if overdueCount >= 2 {
            loops.append(FeedbackLoop(name: "Knowledge Decay", description: "Skipped Reviews → Forgetting → Weaker Foundation → Harder Lessons", strength: min(1.0, Double(overdueCount) / Double(max(1, completedLessons.count))), isPositive: false))
        }
        let recentScores = performanceHistory.suffix(5).map(\.score)
        if recentScores.count >= 5 {
            let minScore = recentScores.min() ?? 0
            let maxScore = recentScores.max() ?? 0
            if maxScore - minScore <= 5 {
                loops.append(FeedbackLoop(name: "Performance Plateau", description: "Same Difficulty → Same Score → No Growth Signal → Same Difficulty", strength: 0.6, isPositive: false))
            }
        }
        return loops
    }
}

// MARK: - Character Trap Messages

extension AppState {
    func trapMessage(for trapType: SystemTrapType) -> String {
        let charId = activeChar
        let messages = Self.trapMessages[charId] ?? Self.trapMessages["byte"]!
        return messages[trapType] ?? "Something feels off in your learning pattern."
    }

    static let trapMessages: [String: [SystemTrapType: String]] = [
        "byte": [
            .driftToLowPerformance: "⚠️ *static* ...scores fragmenting. Pattern: decline. Recalibrate?",
            .successToSuccessful: "⚠️ You keep orbiting the same skills. There are unexplored sectors.",
            .shiftingBurden: "⚠️ New data in, old data fading. Reviews are your memory defrag.",
        ],
        "nova": [
            .driftToLowPerformance: "⚠️ Scores slipping! We're not here to coast — push harder!",
            .successToSuccessful: "⚠️ Comfort zone detected! Real growth is in the skills you avoid.",
            .shiftingBurden: "⚠️ All forward, no reinforcement? Go back and lock in what you learned!",
        ],
        "crash": [
            .driftToLowPerformance: "⚠️ Scores are dropping! Don't settle for 'good enough'!",
            .successToSuccessful: "⚠️ You keep doing easy stuff! Level up to something harder!",
            .shiftingBurden: "⚠️ New challenges but no reviews? Foundation is cracking!",
        ],
        "luna": [
            .driftToLowPerformance: "⚠️ Recent scores are a bit lower... no pressure, but let's improve together?",
            .successToSuccessful: "⚠️ I notice you keep returning to familiar skills... want to try something new?",
            .shiftingBurden: "⚠️ You're moving fast! Let's pause and review — knowledge needs time to settle.",
        ],
        "sage": [
            .driftToLowPerformance: "⚠️ I observe a declining pattern. Pause. Reflect. Then recalibrate.",
            .successToSuccessful: "⚠️ You're in the 'success to successful' trap. Diversify your practice.",
            .shiftingBurden: "⚠️ Challenges without reviews is building on sand. Rebalance.",
        ],
        "glitch": [
            .driftToLowPerformance: "⚠️ Scores going down? That's a bug in your process. Let's hack it.",
            .successToSuccessful: "⚠️ Same skills on repeat? Break the loop — try something weird!",
            .shiftingBurden: "⚠️ All new, nothing reviewed? Even hackers back up their data.",
        ],
        "null": [
            .driftToLowPerformance: "⚠️ Uh oh, scores going brrr... downward! Let's reverse that chaos!",
            .successToSuccessful: "⚠️ You're stuck in a loop! I should know — I LIVE in loops!",
            .shiftingBurden: "⚠️ Reviews? What reviews? Oh... THOSE reviews. Yeah, do those.",
        ],
    ]
}
