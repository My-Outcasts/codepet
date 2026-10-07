// codepet/Models/RoomHandoff.swift
import Foundation

/// byte's one line of handoff, spoken above the room's cards.
///
/// It follows byte's own complete answer, so it reads as a second thought rather than a refusal
/// to answer — the founder sees a companion escalating, not a UI mode switch.
///
/// **It names the departments actually seated.** It was a constant — "Let me bring in product
/// and finance" — on every room. On 1 Oct (build 6, real account) one room seated Finance,
/// Marketing and Sales and the next Marketing and Design, while the line said product and finance
/// both times; Product is not even on the roster. The names come from the routing frame's
/// `agent_meta`, the same source and the same `DepartmentCatalog` names the room card uses, so
/// the line and the card cannot disagree. The challenger and chief of staff are roles, not
/// departments (contract mapping table) and are never named.
enum RoomHandoff {
    ///
    /// **`requested`: the founder asked for the room** (the Team build button). Then there is no
    /// second thought to voice — "Actually — this one needs the whole room" answered a press she
    /// had just made (build 10, 7 Oct) — so byte only says who is coming in.
    static func line(_ language: AppLanguage, routing: VCRouting?, requested: Bool = false) -> String {
        let names = seatedNames(routing)
        if requested {
            guard !names.isEmpty else {
                return language == .vi ? "Mình gọi cả nhóm vào." : "Bringing the team in."
            }
            let list = joined(names, and: language == .vi ? "và" : "and")
            return language == .vi ? "Mình gọi \(list) vào." : "Bringing in \(list)."
        }
        guard !names.isEmpty else {
            return language == .vi
                ? "Thật ra cái này cần cả phòng — để mình gọi cả nhóm vào."
                : "Actually — this one needs the whole room. Let me bring the team in."
        }
        let list = joined(names, and: language == .vi ? "và" : "and")
        return language == .vi
            ? "Thật ra cái này cần cả phòng — để mình gọi \(list) vào."
            : "Actually — this one needs the whole room. Let me bring in \(list)."
    }

    /// Seated departments in routing order, de-duplicated.
    ///
    /// `agent_meta` is what the backend sends (`orchestrate.ts`) and what the room card reads.
    /// A frame without it falls back to the bare `agents` ids, title-cased — the same rule the
    /// card's `roleName` uses, which lands on the catalog's own names for all nine departments.
    static func seatedNames(_ routing: VCRouting?) -> [String] {
        guard let routing else { return [] }
        var out: [String] = []
        func add(_ name: String) { if !out.contains(name) { out.append(name) } }
        if !routing.agentMeta.isEmpty {
            for meta in routing.agentMeta {
                guard let key = meta.departmentKey,
                      let dept = DepartmentCatalog.all.first(where: { $0.key == key }) else { continue }
                add(dept.name)
            }
        } else {
            for id in routing.agents where !roles.contains(id) {
                add(id.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }
                      .joined(separator: " "))
            }
        }
        return out
    }

    /// Agents that take part but are not departments (contract mapping table).
    private static let roles: Set<String> = ["chief_of_staff", "devils_advocate"]

    private static func joined(_ names: [String], and: String) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " \(and) " + names.last!
    }
}
