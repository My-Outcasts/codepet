// codepet/Models/DepartmentPickerRows.swift
import Foundation

/// One row of the department picker: a pet, and every department it speaks for.
///
/// Nova covers Marketing and Sales; Glitch covers Operations and Legal. The old
/// `Menu` iterated departments, so those two pets rendered twice each — same sprite,
/// same name, nothing saying they were one character with two jobs.
struct PetRow: Identifiable, Equatable {
    let petId: String
    let petName: String
    let departments: [Department]
    var id: String { petId }
}

/// The picker's rows, derived from the same two sources the menu already read.
///
/// **Why this is a type and not a `ForEach` over a dictionary.** `DepartmentCompanions.map`
/// is a `[String: String]`, and dictionary iteration order is not stable across launches —
/// grouping inline would reshuffle the roster on the founder every time they opened the
/// control. Order is taken from `rosterOrder` and pinned by a test.
enum DepartmentPickerRows {

    /// Pets in first-appearance order over `DepartmentMenu.rosterOrder`, each carrying its
    /// departments in roster order.
    ///
    /// A roster department with no pet is SKIPPED rather than given a portrait-less row.
    /// None exists today — `rosterOrder` already filters Product, the only petless
    /// department — and `DepartmentPickerRowsTests.testGroupingCoversTheRosterExactlyOnce`
    /// goes red the moment one appears, which is the right way to learn that a decision
    /// is owed rather than shipping a blank face.
    static var rows: [PetRow] {
        var order: [String] = []
        var byPet: [String: [Department]] = [:]
        for dep in DepartmentMenu.rosterOrder {
            guard let pet = DepartmentMenu.pet(for: dep) else { continue }
            if byPet[pet] == nil { order.append(pet) }
            byPet[pet, default: []].append(dep)
        }
        return order.compactMap { pet in
            guard let name = PetCharacter.all[pet]?.name else { return nil }
            return PetRow(petId: pet, petName: name, departments: byPet[pet] ?? [])
        }
    }
}
