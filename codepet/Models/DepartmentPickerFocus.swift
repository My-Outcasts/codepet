// codepet/Models/DepartmentPickerFocus.swift
import Foundation

/// Where the keyboard is in the picker.
enum PickerFocus: Equatable {
    case anyone
    case chip(pet: Int, dept: Int)
}

/// Keyboard traversal over the picker's rows.
///
/// **Pure, and deliberately so.** `Menu` gave arrow-key traversal away for free; the
/// popover writes it. Kept out of the view because a SwiftUI row cannot be asserted on
/// from a test and a function can — the same reason `DepartmentMenu` is a type.
///
/// Every move CLAMPS rather than wraps. Wrapping would put Sales one keypress from
/// Marketing in both directions, which reads as the focus teleporting rather than moving.
enum DepartmentPickerFocus {

    static func down(from focus: PickerFocus, rows: [PetRow]) -> PickerFocus {
        guard !rows.isEmpty else { return .anyone }
        switch focus {
        case .anyone:
            return .chip(pet: 0, dept: 0)
        case .chip(let pet, _):
            return .chip(pet: min(pet + 1, rows.count - 1), dept: 0)
        }
    }

    static func up(from focus: PickerFocus, rows: [PetRow]) -> PickerFocus {
        switch focus {
        case .anyone:
            return .anyone
        case .chip(let pet, _):
            return pet == 0 ? .anyone : .chip(pet: pet - 1, dept: 0)
        }
    }

    static func right(from focus: PickerFocus, rows: [PetRow]) -> PickerFocus {
        guard case .chip(let pet, let dept) = focus, pet < rows.count else { return focus }
        return .chip(pet: pet, dept: min(dept + 1, rows[pet].departments.count - 1))
    }

    static func left(from focus: PickerFocus, rows: [PetRow]) -> PickerFocus {
        guard case .chip(let pet, let dept) = focus else { return focus }
        return .chip(pet: pet, dept: max(dept - 1, 0))
    }

    /// The department under the cursor, or nil on the Anyone row.
    static func department(at focus: PickerFocus, rows: [PetRow]) -> Department? {
        guard case .chip(let pet, let dept) = focus,
              pet < rows.count, dept >= 0, dept < rows[pet].departments.count else { return nil }
        return rows[pet].departments[dept]
    }

    /// Where `department` sits in `rows`, or `.anyone` when no row carries it.
    ///
    /// The inverse of `department(at:rows:)`. It lives here rather than in the view so the
    /// not-found case is pinned by a test: a department absent from every row falls back to
    /// `.anyone` rather than to an index that would point at the wrong pet.
    static func locate(_ department: Department, in rows: [PetRow]) -> PickerFocus {
        for (petIndex, row) in rows.enumerated() {
            if let slot = row.departments.firstIndex(where: { $0.key == department.key }) {
                return .chip(pet: petIndex, dept: slot)
            }
        }
        return .anyone
    }
}
