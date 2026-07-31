// codepet/Models/DepartmentCompanions.swift
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

    /// The first department whose NAME appears in `text` (case-insensitive), so a
    /// free-text mention ("help me with marketing") can bring in the right pet.
    /// Matches on the human name only (not the short key) to avoid substring
    /// false positives; the department chip remains the precise trigger.
    static func mentionedDeptKey(in text: String) -> String? {
        let lower = text.lowercased()
        return DepartmentCatalog.all.first { lower.contains($0.name.lowercased()) }?.key
    }
}
