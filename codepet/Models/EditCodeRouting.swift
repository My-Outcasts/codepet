import Foundation

/// Whether a chat ask should route to the LOCAL coding agent (`edit_code`) rather
/// than a normal cloud turn: true only when the founder picked the Engineering
/// department AND a project is linked. Pure.
enum EditCodeRouting {
    static func shouldRoute(department: Department?, projectLinked: Bool) -> Bool {
        department?.key == "eng" && projectLinked
    }
}
