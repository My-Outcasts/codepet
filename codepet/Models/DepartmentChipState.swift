// codepet/Models/DepartmentChipState.swift
import Foundation

/// How one department chip renders: outlined, dashed, or filled.
///
/// Three states differing in SHAPE, not only in colour, so the distinction survives
/// colour-blindness without adding glyphs to a 24pt chip.
enum DepartmentChipState: Equatable {
    /// Outlined, muted. Not this turn's department.
    case idle
    /// Dashed border, tinted fill. Codepet guessed this; the founder has not confirmed it.
    case suggested
    /// Filled in the pet's colour. The founder chose this.
    case picked
}

extension DepartmentChipState {

    /// **The rule the old menu got wrong.** `ChatComposer.deptRow` checkmarked on
    /// `armed ?? suggestedDept`, which renders a guess and a pick identically — so the
    /// menu presented Codepet's guess as the founder's decision, eighteen points above a
    /// composer chip that was correctly drawing the same state dashed. One control called
    /// it a guess and the other called it settled.
    ///
    /// The suppression on the last line mirrors `departmentControl`'s
    /// `activeSuggestion = armed == nil ? suggestion : nil`: a guess is only ever shown
    /// when nothing is armed, so two chips can never both claim the turn.
    static func of(_ department: Department,
                   armed: Department?,
                   suggested: Department?) -> DepartmentChipState {
        if armed?.key == department.key { return .picked }
        if armed == nil, suggested?.key == department.key { return .suggested }
        return .idle
    }
}
