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
    static func mentionedDeptKey(in text: String) -> String? {
        let lower = text.lowercased()
        return DepartmentCatalog.all.first {
            map[$0.key] != nil && lower.contains($0.name.lowercased())
        }?.key
    }
}
