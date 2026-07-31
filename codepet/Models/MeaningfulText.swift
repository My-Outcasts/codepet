// codepet/Models/MeaningfulText.swift
import Foundation

/// Placeholder-junk filter for founder-supplied brief text, mirroring the web's
/// `meaningfulText` / `cleanCompanyName` guards. Onboarding lets people type anything, so a
/// company one-liner of "12" or a name that's really an email must not reach the UI — the web
/// drops those and falls back to its generic copy, and the native Overview must do the same.
enum MeaningfulText {
    /// The trimmed value, or nil when it is placeholder-y: empty, a single character,
    /// all digits, or an email address.
    static func clean(_ raw: String?) -> String? {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return nil }
        if t.allSatisfy({ $0.isNumber }) { return nil }
        if t.contains("@"), t.contains(".") { return nil }
        return t
    }
}
