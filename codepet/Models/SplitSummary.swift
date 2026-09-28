// codepet/Models/SplitSummary.swift
import Foundation

/// One sentence for where a landed room splits (CP-030), in place of one line per department pair.
///
/// The classifier emits a conflict per PAIR, so one department holding a blocker against three
/// others is three rows, and four departments each holding a condition is six. The landed card
/// listed them all in orange ("Product ↔ Design · blocker" ×6) above a narrative that called it
/// "two live fights" — the list was louder than the answer and said less. The narrative under it
/// (`the_real_disagreement`, verbatim, rule 3) is unchanged; the pairs themselves are still in the
/// room's full record.
enum SplitSummary {
    static func line(_ conflicts: [VCConflict], name: (String) -> String, lang: AppLanguage) -> String? {
        let pairs = conflicts.filter { $0.kind != "ALIGNED" }
        guard !pairs.isEmpty else { return nil }
        let vi = lang == .vi

        var depts: [String] = []
        for p in pairs { for d in [p.a, p.b] where !depts.contains(d) { depts.append(d) } }
        let hard = pairs.allSatisfy { $0.kind == "BLOCKER" }

        if pairs.count == 1 {
            let (a, b) = (name(pairs[0].a), name(pairs[0].b))
            if vi { return hard ? "\(a) và \(b) bất đồng ở một điểm cứng." : "\(a) và \(b) nhìn việc này khác nhau." }
            return hard ? "\(a) and \(b) disagree on a hard point." : "\(a) and \(b) see this differently."
        }

        // One department in every pair: it is the objection, the rest agree among themselves.
        let hubs = depts.filter { d in pairs.allSatisfy { $0.a == d || $0.b == d } }
        if hubs.count == 1 {
            let hub = name(hubs[0])
            return vi ? "\(hub) có một phản đối cứng mà các phòng ban khác không có."
                      : "\(hub) holds a hard objection the others don't share."
        }

        let list = listed(depts.map(name), vi: vi)
        let complete = pairs.count == depts.count * (depts.count - 1) / 2
        if hard && complete {
            let all = depts.map(name).joined(separator: ", ")
            return vi ? "\(depts.count) phòng ban đều giữ một điều kiện cứng: \(all)."
                      : "\(depts.count) departments each hold a hard condition: \(all)."
        }
        return vi ? "\(list) bất đồng ở một số điểm." : "\(list) disagree on parts of this."
    }

    private static func listed(_ names: [String], vi: Bool) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + (vi ? " và " : " and ") + names.last!
    }
}
