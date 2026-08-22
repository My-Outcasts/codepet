// codepet/Models/DepartmentMenu.swift
import Foundation

/// The contents of the composer's departments menu — spec §4.
///
/// **Why this is a type and not just view code.** A SwiftUI `Menu`'s rows cannot be
/// asserted on from a test, and the one rule this control must never break is
/// testable: the pet a row shows has to be the pet that signs the reply. That rule
/// has exactly one home, `DepartmentCompanions.specialistId`, which is also what
/// `CompanyStore.actingSpecialist` calls on send. This type reads it and nothing
/// else, so the menu and the answer cannot disagree.
enum DepartmentMenu {

    /// All eight, in catalog order. `product` is absent because `roster` filters it:
    /// it has no pet and `dept-product.png` is a byte-identical copy of
    /// `dept-eng.png`, so a row for it would wear Engineering's identity.
    static var rosterOrder: [Department] { DepartmentCatalog.roster }

    /// The pet this row summons, or nil when the turn would stay with the host.
    /// Delegates — see the type comment for why it must.
    static func pet(for department: Department, host: String) -> String? {
        DepartmentCompanions.specialistId(for: department.key, host: host)
    }

    /// `crash · Engineering`. The pet's name leads because that is the order the
    /// reply is signed in (`CopilotChatView.headerName` renders `Nova · Marketing`),
    /// so the row and the answer read alike. No mapped specialist means the
    /// department alone — the row never promises a pet that will not appear.
    static func rowTitle(_ department: Department, host: String) -> String {
        guard let id = pet(for: department, host: host),
              let name = PetCharacter.all[id]?.name else { return department.name }
        return "\(name) · \(department.name)"
    }

    /// The armed button's own label. Same string as the row, so picking a row and
    /// reading the button back cannot look like two different choices.
    static func armedLabel(_ department: Department, host: String) -> String {
        rowTitle(department, host: host)
    }

    static func restLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Phòng ban" : "Departments"
    }

    /// The off state, made nameable. Deselecting used to be reachable only by
    /// clicking an armed chip a second time; letting byte route it is a real choice
    /// and it should be a row you can pick, with a checkmark saying it is what you
    /// have.
    static func anyoneLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Ai cũng được — byte tự chọn" : "Anyone — byte routes it"
    }

    static func anyoneDetail(_ lang: AppLanguage) -> String {
        lang == .vi ? "Để Codepet chọn người trả lời" : "Let Codepet pick who answers"
    }

    static func clearHelp(_ lang: AppLanguage) -> String {
        lang == .vi ? "Bỏ chọn phòng ban" : "Clear the department"
    }
}
