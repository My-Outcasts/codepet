// codepet/Models/BriefContext.swift
import Foundation

/// Composes a `CompanyBrief` into a single plain-language paragraph the
/// companion writes from. Verbatim logic port of the web `briefToContext`
/// (lib/ai/brief.ts): same slice limits, same sentence assembly, and the same
/// contract of returning nil when there is no usable product signal.
enum BriefContext {
    static func compose(_ brief: CompanyBrief?) -> String? {
        guard let b = brief else { return nil }
        func str(_ v: String?, _ n: Int) -> String {
            guard let v = v else { return "" }
            return String(v.trimmingCharacters(in: .whitespacesAndNewlines).prefix(n))
        }
        let name = str(b.projectName, 120)
        let oneLiner = str(b.oneLiner, 240)
        let summary = str(b.summary, 400)
        let notes = str(b.notes, 800)
        let categories = Array((b.categories ?? []).prefix(6))
        let audience = str(b.audience, 160)
        let link = str(b.link, 200)
        if name.isEmpty && oneLiner.isEmpty && summary.isEmpty && notes.isEmpty { return nil }

        func dot(_ s: String) -> String { s.hasSuffix(".") ? s : s + "." }
        var parts: [String] = ["The company is \(name.isEmpty ? "the founder's product" : name)."]
        // byte's enriched summary is a distillation of the one-liner + notes, so
        // when it exists it REPLACES both (avoid repeating the description ~3x).
        if !summary.isEmpty {
            parts.append(dot(summary))
        } else if !oneLiner.isEmpty {
            parts.append(dot(oneLiner))
        }
        if !categories.isEmpty {
            parts.append("It is a \(categories.joined(separator: " / ").lowercased()) product.")
        }
        if !audience.isEmpty { parts.append("It's for \(audience).") }
        if !notes.isEmpty && summary.isEmpty { parts.append(dot(notes)) }
        if !link.isEmpty { parts.append("Reference: \(link).") }
        var who: [String] = []
        let role = str(b.role, 80)
        let stage = str(b.stage, 80)
        if !role.isEmpty { who.append("a \(role.lowercased())") }
        if !stage.isEmpty { who.append("at the \(stage.lowercased()) stage") }
        if !who.isEmpty { parts.append("The founder is \(who.joined(separator: ", ")).") }
        let founderName = str(b.founderName, 80)
        if !founderName.isEmpty { parts.append("Their name is \(founderName).") }
        return parts.joined(separator: " ")
    }
}
