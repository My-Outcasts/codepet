import Foundation

/// The streaming-state label copy. Pure + localized.
///
/// **Names the pet, because the row no longer shows one.** The working row used to be an
/// orb plus a generic verb, which told the founder that something was happening and nothing
/// about who was doing it — on a product whose whole claim is that eight departments each
/// have their own voice. Founder call, 7 Sep: drop the orb, say the name.
///
/// Still never fabricates. A missing pet or a missing title each fall back rather than
/// inventing one, so the row degrades to exactly the old copy instead of asserting a
/// specialist that is not working.
enum ChatThinkingLabel {
    static func text(petName: String? = nil, taskTitle: String?, language: AppLanguage) -> String {
        let pet = petName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPet = !(pet ?? "").isEmpty
        let hasTitle = !(title ?? "").isEmpty

        switch (hasPet, hasTitle) {
        case (true, true):
            return language == .vi ? "\(pet!) đang soạn \(title!)…" : "\(pet!) is drafting \(title!)…"
        case (true, false):
            return language == .vi ? "\(pet!) đang làm…" : "\(pet!) is on it…"
        case (false, true):
            return language == .vi ? "Đang soạn \(title!)…" : "Drafting \(title!)…"
        case (false, false):
            return language == .vi ? "Đang xử lý…" : "Working on it…"
        }
    }
}
