import Foundation

/// Maps each business department to the pet that speaks for it. Casting is by domain fit
/// (see PetCharacter.domain) and is freely editable — nothing depends on the exact cast.
///
/// **There is no host entry, and no host rule.** Codepet is the host: a general turn carries
/// no `companionId` and `CopilotChatView.headerName` signs it `CodepetBrand.name`. The pets are
/// department characters and nothing else.
///
/// This map used to be read through `specialistId(for:host:)`, which returned nil whenever a
/// department's pet WAS the founder's own companion — "announcing a handoff to yourself says
/// nothing". That premise assumed the host signs replies with a pet's name. It does not, and
/// never did. What the rule actually did was hide attribution from exactly one founder per
/// department, and once `byte` took Engineering — with every founder's companion defaulting to
/// `byte` since the onboarding picker was removed on 14 Aug — it would have hidden Engineering's
/// pet from everybody.
///
/// The invariant it was written to protect survives without it, more strongly: a chip promising
/// a pet that the send then declines to hand off to is a lie the founder can see in one tap, and
/// with one unconditional resolver the chip and the send have no input on which they can differ.
enum DepartmentCompanions {
    /// deptKey (DepartmentCatalog) → companionId (PetCharacter).
    static let map: [String: String] = [
        "eng": "byte",       // data flow, state, algorithms — and the product IS software
        "design": "luna",    // Designer (UX/UI)
        "mkt": "nova",       // Firestarter — launches, energy
        "sales": "nova",     // growth energy (shares the marketing persona)
        "support": "sage",   // calm, patient, methodical
        "fin": "crash",      // runway is a shipping constraint, not an essay
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
    /// it maps to nothing, "ask design about my product page" silently lost luna · Design.
    /// Skipping here keeps the next match reachable. The alternative — mapping a companion to
    /// the word "product" — would hijack one of the most common words a founder types.
    ///
    /// That example used to read "what should the design of my product page be?", and the
    /// addressing rule below (added later, Aug 7) declines that sentence on its own — it names
    /// design without addressing it. The comment outlived the behaviour it described, and so did
    /// the test under it, which had been red on `main` since. Both now use an addressed phrasing,
    /// which is the only kind that reaches the shadowing this paragraph is about.
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
    ///
    /// Every entry here takes a PERSON as its object ("ask marketing", "check with support") or
    /// makes the department the subject of a question ("can engineering ship this?"). That is the
    /// closest a word-level heuristic gets to intent, and it is the whole guard — so a word that
    /// merely tends to sit next to a department name does not belong in this list.
    ///
    /// Five did, and they re-opened the bug the addressing rule was written to close. `for`,
    /// `from`, `with` and `have` are ordinary prepositions and `do` an ordinary auxiliary; they
    /// govern the department name as a plain NOUN, which is how a founder describing their company
    /// uses those words. Measured Aug 10 against real-shaped messages: "we have support from two
    /// angel investors" handed the turn to Sage · Support, "our runway comes from sales, not
    /// funding" to Nova · Sales, "I need a landing page for marketing purposes" to Nova ·
    /// Marketing, and "I'm happy with design so far" to Luna · Design. Six of twelve sentences
    /// summoned a pet nobody asked for — the same failure as the Aug 7 bakery paste, arriving
    /// through the fix for it. `does`/`do` go too; `what does`/`what do` already carry the
    /// addressed form and bare `do` only ever led false positives ("do design tokens matter?").
    ///
    /// The residual is deliberate and lands the safe way: "can design be simpler?" still summons
    /// Luna, because the topic IS design. A pet answering a question inside its own department is
    /// not the failure this guards against; a pet answering because the founder pasted a sentence
    /// containing its name is. DepartmentCompanionsTests + DepartmentAddressingTests hold both
    /// directions — the false positives above and the forms that must keep working.
    ///
    /// `help me with` / `help with` are here because bare `with` is not. "help me with marketing"
    /// is this function's original motivating example (see the doc comment above) and it IS a
    /// request aimed at a department — it just happens to reach it through the same preposition
    /// that "I'm happy with design so far" reaches a plain noun through. The verb is what carries
    /// the intent, so the verb is what's matched.
    private static let addressingPrefixes = [
        "ask", "asking", "tell", "bring in", "bring", "check with", "loop in",
        "hand to", "hand this to", "help me with", "help with",
        "what does", "what do", "what would", "can", "could", "should",
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
