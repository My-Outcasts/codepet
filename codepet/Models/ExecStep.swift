import Foundation

/// One line of a run's execute log.
///
/// `kind` replaces the label-prefix sniffing this used to rely on (`label.lowercased()
/// .hasPrefix("checkpoint")`), which put presentation logic in two views and made a
/// checkpoint impossible to express in Vietnamese. It is defaulted so any archived
/// `ExecStep` still decodes.
///
/// The three kinds mirror the web's `LogStep` (`t` / `mono` / `ck` in `lib/helpers.ts`), which
/// is the reference this log is built against — one narrative row, one terminal row, one
/// checkpoint. What deliberately does NOT come across from the web is its invented specifics:
/// its `Ran N actions` counter is `3 + (label.length % 6)` summed, its diff sizes are
/// `8 + (title.length % 9)`, and "218 tests passed" is a constant. Native shows a true step
/// count, and a `mono` row only where there is real data behind it — a coding run's actual
/// tool steps and actual changed files. Founder call, Aug 5: structure yes, invented numbers no.
struct ExecStep: Identifiable, Equatable, Codable {
    enum Kind: String, Equatable, Codable {
        /// Narrative: what the agent is doing, in the founder's language. Renders with a ✓.
        case normal
        /// Terminal-style, for real tool activity. Renders monospaced behind a `›`.
        case mono
        /// The beat where the run stopped to check its own work. Renders as a gold dot.
        case checkpoint
    }

    let id: String
    let label: String
    var done: Bool
    var kind: Kind

    init(id: String = UUID().uuidString, label: String, done: Bool = false, kind: Kind = .normal) {
        self.id = id
        self.label = label
        self.done = done
        self.kind = kind
    }

    /// Older payloads carry no `kind`, and a checkpoint written before this field existed is
    /// still recognisable by its label — the exact rule the views used to apply themselves.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind)
            ?? (label.lowercased().hasPrefix("checkpoint") ? .checkpoint : .normal)
    }
}
