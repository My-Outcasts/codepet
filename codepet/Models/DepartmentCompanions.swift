import Foundation

/// Maps each business department to a specialist companion persona. `byte` is the
/// host/generalist and is intentionally NOT assigned to any department, so it can
/// hand off to a specialist. Casting is by domain fit (see PetCharacter.domain)
/// and is freely editable — the handoff mechanic doesn't depend on the exact cast.
enum DepartmentCompanions {
    /// deptKey (DepartmentCatalog) → companionId (PetCharacter).
    static let map: [String: String] = [
        "eng": "crash",      // Backend Dev — builds & ships
        "design": "luna",    // Designer (UX/UI)
        "mkt": "nova",       // Firestarter — launches, energy
        "sales": "nova",     // growth energy (shares the marketing persona)
        "support": "sage",   // calm, patient, methodical
        "fin": "sage",       // analytical — "real data, not vibes"
        "ops": "glitch",     // DevOps — automation
        "legal": "glitch",   // rules & edges
    ]

    static func companionId(for deptKey: String) -> String? { map[deptKey] }

    /// The first department whose NAME appears in `text` (case-insensitive) AND has a
    /// companion to bring in, so a free-text mention ("help me with marketing") gets the
    /// right pet. Matches on the human name only (not the short key) to avoid substring
    /// false positives; the department chip remains the precise trigger.
    ///
    /// Unmapped departments are SKIPPED rather than returned-and-dropped. Adding
    /// `product` to the catalog (for the Virtual Company's `department_key`) put an
    /// entry with no companion at index 1, and because the caller
    /// (`CompanyStore.actingSpecialist`) resolves the single returned key and gives up if
    /// it maps to nothing, "what should the design of my product page be?" silently lost
    /// luna · Design. Skipping here keeps the next match reachable. The alternative —
    /// mapping a companion to the word "product" — would hijack one of the most common
    /// words a founder types.
    /// A department has to be ADDRESSED, not merely mentioned.
    ///
    /// This used to be `lower.contains(dept.name.lowercased())` over the whole message, and on
    /// Aug 7 that handed a Sales task to Support because the founder had pasted a bakery's habits
    /// — *"emails me when something's off instead of using support"*. One incidental word inside
    /// quoted customer data changed who answered.
    ///
    /// Two defects in that line, both fixed here. It matched SUBSTRINGS, so "designed",
    /// "operational" and "supporting" all triggered a handoff; and any occurrence anywhere counted
    /// as intent.
    ///
    /// The rule now: the department name must appear as a whole word AND in a phrase that
    /// addresses it — "ask marketing", "what does finance think", "bring in legal", "marketing's
    /// take", or the message opening with the name. Everything else answers as the host, which is
    /// the safe direction to fail: an un-handed-off answer looks normal, while the wrong pet
    /// answering a question does not. The department chip remains the precise, explicit trigger.
    static func mentionedDeptKey(in text: String) -> String? {
        let lower = text.lowercased()
        return DepartmentCatalog.all.first { dept in
            guard map[dept.key] != nil else { return false }
            return isAddressed(dept.name.lowercased(), in: lower)
        }?.key
    }

    /// Verbs and forms that mean the founder is talking TO a department rather than about a word.
    private static let addressingPrefixes = [
        "ask", "asking", "tell", "get", "have", "bring in", "bring", "check with", "loop in",
        "hand to", "hand this to", "for", "from", "with", "what does", "what do", "what would",
        "can", "could", "should", "does", "do",
    ]

    private static func isAddressed(_ name: String, in text: String) -> Bool {
        var search = text.startIndex
        while let r = text.range(of: name, range: search..<text.endIndex) {
            defer { search = r.upperBound }
            // Whole word only: "support" must not match inside "supporting", and "design" must not
            // match inside "designed".
            let beforeOK = r.lowerBound == text.startIndex
                || !text[text.index(before: r.lowerBound)].isLetter
            let afterOK = r.upperBound == text.endIndex || !text[r.upperBound].isLetter
            guard beforeOK, afterOK else { continue }

            // Opening the message with the name is addressing it.
            if r.lowerBound == text.startIndex { return true }
            // A possessive — "marketing's take on this".
            if text[r.upperBound...].hasPrefix("'s") { return true }

            let before = text[..<r.lowerBound]
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,:—-\n\t"))
                .lowercased()
            if addressingPrefixes.contains(where: { before.hasSuffix($0) }) { return true }
        }
        return false
    }
}
