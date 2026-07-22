// codepet/Models/OnboardingReveal.swift
import Foundation

/// The first-run reveal summary (wizard step 7), adapted to the native task model.
/// Native has no "departments" in the product (the Overview is phase-based), so the
/// reveal is derived from the scaffolded roadmap tasks. Pure; unit-tested.
struct OnboardingReveal: Equatable {
    /// True when the scaffold produced any tasks (vs. the fail-open empty fallback).
    let ok: Bool
    /// Open (not-done) task count across the roadmap.
    let taskCount: Int
    /// Up to 3 open task titles, for the reveal rows.
    let sampleTasks: [String]

    static let empty = OnboardingReveal(ok: false, taskCount: 0, sampleTasks: [])

    static func build(tasks: [RoadmapTask]) -> OnboardingReveal {
        guard !tasks.isEmpty else { return .empty }
        let open = tasks.filter { !$0.done }
        return OnboardingReveal(
            ok: true,
            taskCount: open.count,
            sampleTasks: Array(open.prefix(3).map { $0.title })
        )
    }
}
