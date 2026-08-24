// codepet/Models/DepartmentSuggestionLabel.swift
import Foundation

/// The hover sentence on a suggested department chip.
///
/// A guess the founder cannot interrogate is a guess they have to trust or fight. Naming the
/// word that fired turns a wrong suggestion into something obviously wrong-for-a-reason —
/// "you mentioned \"support\"" on a sentence about investors explains itself and gets
/// dismissed without alarm.
///
/// Its own type because a SwiftUI `.help()` string is unreachable from a test, exactly as
/// `DepartmentMenu` is its own type for the menu rows.
enum DepartmentSuggestionLabel {
    static func help(tier: DepartmentRouter.Tier,
                     matched: String?,
                     pet: String?,
                     department: Department,
                     lang: AppLanguage) -> String {
        let who = pet.flatMap { PetCharacter.all[$0]?.name }
            .map { "\($0) · \(department.name)" } ?? department.name

        switch tier {
        case .carryOver:
            return lang == .vi ? "Tiếp tục với \(who)" : "Continuing with \(who)"
        case .topical, .addressed:
            // No term, no claim of one. `you mentioned “”` would be worse than saying nothing
            // about why — it invents a quotation the founder never wrote.
            guard let matched, !matched.isEmpty else {
                return lang == .vi ? "Gợi ý — \(who)" : "Suggested — \(who)"
            }
            return lang == .vi
                ? "Gợi ý — bạn có nhắc “\(matched)”"
                : "Suggested — you mentioned “\(matched)”"
        }
    }
}
