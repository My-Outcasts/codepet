// codepet/Models/DevRunStage.swift
import Foundation

/// What Developer's work pane draws for a run — and which phase is allowed to
/// start itself.
///
/// **Why this is a type and not an `if` inside the view.** The work pane shipped
/// rendering only three of the eight phases, so a run reached `.previewing` and sat
/// there reading `PREPARING` forever: `execute()` was called from exactly one place
/// in the app, `CodeRunCardView`, which the Ask transcript renders and Developer
/// does not. Nothing failed, nothing was logged, and the walkthrough narrated a
/// build flow over a screen that never moved. A phase router that lives in a `switch`
/// inside `body` cannot be asserted; this can, so a phase added later that nobody
/// draws is a red test rather than a state that silently does nothing.
enum DevRunStage: Hashable {
    /// No run at all.
    case idle
    /// Proposed with nothing linked — Developer has nowhere to work.
    case dormant
    /// The plan preview. The founder confirms before anything executes.
    case plan
    /// Executing: `.readyToRun` (about to) or `.running`.
    case working
    /// Diffs are ready and the gate is open.
    case gate
    /// It landed.
    case landed
    /// The founder rejected the diff.
    case dropped
    case failed(String)

    static func stage(for phase: EditCodePhase?) -> DevRunStage {
        guard let phase else { return .idle }
        switch phase {
        case .noProject:              return .dormant
        case .previewing:             return .plan
        case .readyToRun, .running:   return .working
        case .reviewing:              return .gate
        case .committed:              return .landed
        case .discarded:              return .dropped
        case .failed(let why):        return .failed(why)
        }
    }

    /// **Only `.readyToRun` starts itself.**
    ///
    /// `.readyToRun` means the planner judged the change small and safe enough that
    /// the diff review IS the gate, so waiting for a second confirmation would be
    /// ceremony. `.previewing` is the opposite judgement — multi-file or needs a
    /// shell — and auto-running it would execute a plan the founder was shown but
    /// never agreed to. The distinction is the whole reason `needsPreview` exists,
    /// and it is one character away from being lost in a view.
    static func startsItself(_ phase: EditCodePhase?) -> Bool {
        phase == .readyToRun
    }
}
